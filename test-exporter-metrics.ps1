function Q($q) {
  docker run --rm --network=opentelemetry-demo curlimages/curl:latest -s "http://prometheus:9090/api/v1/query?query=$q"
}
Write-Host "=== sent_log_records by exporter ==="
Q 'sum%20by%20(exporter)(otelcol_exporter_sent_log_records_total)'
Write-Host "`n=== failed_log_records by exporter ==="
Q 'sum%20by%20(exporter)(otelcol_exporter_send_failed_log_records_total)'
Write-Host "`n=== queue size by exporter ==="
Q 'otelcol_exporter_queue_size'
Write-Host "`n=== queue capacity by exporter ==="
Q 'otelcol_exporter_queue_capacity'
