# Troubleshooting: `postgresql*` metrics missing in `grafana-cvz`

## Summary

`postgresql*` metrics (and intermittently other metrics) never appeared in
`grafana-cvz` / `prometheus-cvz`, even though Clarivize's logs/UX showed them being
exported. The root cause was **stale sample timestamps** being rejected by
`prometheus-cvz` as *"too old sample"*, which caused the whole OTLP write request —
including the healthy `postgresql` samples bundled in it — to be dropped.

The issue is fixed by forcing `otel-collector-cvz` to overwrite every metric
datapoint timestamp with the current time before exporting to `prometheus-cvz`.

## Symptoms observed

- `grafana-cvz`: no `postgresql*` series; `count({__name__=~"postgresql_.*"})` returned empty.
- `prometheus-cvz` logs: repeated
  `level=ERROR source=write_handler.go:652 msg="Error appending remote write" err="too old sample; too old sample; ..."`
  plus `Overlapping blocks found during reloadBlocks` and `out of order exemplar` warnings.
- `otel-collector-cvz` logs: repeated
  `Exporting failed. Dropping data. ... otelcol.component.id=otlp_http/prometheus ... HTTP Status Code 500 ... dropped_items: 143/796/...`.

## The telemetry path

```
demo services ─▶ otel-collector-od ─▶ clarivize (sampling/reduction) ─▶ otel-collector-cvz ─▶ prometheus-cvz ─▶ grafana-cvz
```

The CVZ stack only stores what Clarivize forwards to `otel-collector-cvz`.

## Root cause

1. `prometheus-cvz` has out-of-order ingestion enabled with a 30-minute window
   (`storage.tsdb.out_of_order_time_window: 30m` in
   [Clarivize/prometheus-config_cvz.yaml](prometheus-config_cvz.yaml)). Any sample whose
   timestamp is older than `head_max_time - 30m` is rejected with
   **`too old sample`**.
2. The `head_max_time` is continuously driven to ~now by the many high-frequency
   demo metrics, so the rejection boundary is effectively **now − 30 minutes**.
3. Clarivize replays **sampled / low-churn** metric datapoints (many `postgresql.*`
   series barely change — e.g. `postgresql.deadlocks`, connection gauges) with their
   **original receiver-start timestamps**. In the captured debug output these datapoints
   carried a `Timestamp:` of `17:28` while wall-clock was `21:1x` — roughly **3h47m old**,
   far beyond the 30-minute window.
4. Prometheus's OTLP endpoint returns **HTTP 500 for the entire write request** when it
   contains any rejected sample. `otel-collector-cvz` treats this as a permanent error and
   **drops the whole batch** — including the fresh `postgresql` sums (which arrive with
   *current* timestamps) that were bundled in the same request. `postgresql` is therefore
   *collateral damage*, which is why it is consistently missing while noisier metrics
   (streamed in requests without stale samples) survive.

### Ruled out
- **Prometheus created-timestamp zero-injection**: not the cause. The
  `created-timestamp-zero-ingestion` feature is **off by default** and is scrape-only
  (not OTLP), so the old `StartTimestamp` (17:28) was a red herring. The offending
  timestamps are on the **datapoints themselves**, not the start timestamps.
- **Insufficient OOO window**: raising the 30-minute window would not help — the replayed
  timestamps are hours old and would keep drifting further behind real time.

## How it was diagnosed

1. Enabled debug logging (temporary):
   - `otel-collector-cvz` debug exporter `verbosity: detailed`.
   - `prometheus-cvz` `--log.level=debug`.
2. Compared `prometheus-cvz` head bounds vs. now via
   `GET /api/v1/status/tsdb` — head max ≈ now, so the reject boundary was now − 30m.
   No `postgresql*` in `seriesCountByMetricName`.
3. Parsed `otel-collector-cvz` detailed metric dumps and found datapoint `Timestamp:`
   values as old as the receiver start (`17:28`), while `postgresql.operations` etc.
   themselves carried current timestamps → confirmed whole-request rejection / collateral drop.

## Fix applied

Added an OTTL `transform` processor to the **metrics** pipeline of
[Clarivize/otelcol-config_cvz.yml](otelcol-config_cvz.yml) that stamps every datapoint with
the collector's current time immediately before export:

```yaml
processors:
  transform/force_current_timestamp:
    error_mode: ignore
    metric_statements:
      - context: datapoint
        statements:
          - set(time, Now())

service:
  pipelines:
    metrics:
      receivers: [otlp, spanmetrics]
      processors: [resourcedetection, memory_limiter, transform/force_current_timestamp]
      exporters: [otlp_http/prometheus, debug]
```

This guarantees every sample is inside the out-of-order window, so
`prometheus-cvz` never returns `too old sample` and never 500s the batch. This is the
practical equivalent of *"force prometheus to use ingestion time"* — implemented on the
collector side because the Prometheus OTLP receiver has no native ingest-time override.

### Trade-off
All exported metric timestamps are normalized to the collector's export time. This keeps
every series visible and current, but the original sub-second/emit spacing of sampled
datapoints is lost, so `rate()`/`increase()` reflect the export cadence rather than the
original scrape cadence. Acceptable for this parallel visualization stack.

## Verification

| Check | Before | After |
|-------|--------|-------|
| `count({__name__=~"postgresql_.*"})` | empty | 40–80+ series |
| `postgresql_backends` value | absent | present (e.g. 3, 4) |
| `prometheus-cvz` "too old sample" / 30s | ~10–26 | 0 |
| `otel-collector-cvz` "Dropping data" / 30s | several | 0 |

All 27 `postgresql*` metric families are now present in `prometheus-cvz` and queryable in
`grafana-cvz`.

## Re-enabling debug logging (if needed later)

The diagnostic debug logging was reverted to keep steady-state logs quiet. To re-enable:
- `otel-collector-cvz`: set `verbosity: detailed` under `exporters.debug` in
  [otelcol-config_cvz.yml](otelcol-config_cvz.yml).
- `prometheus-cvz`: add `- --log.level=debug` to its `command` in
  [../docker-compose.yml](../docker-compose.yml).
Then `docker compose up -d --no-deps --force-recreate otel-collector-cvz prometheus-cvz`.
