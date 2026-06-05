$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000000
$body = '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"manual-test"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"' + $now + '","severityText":"INFO","body":{"stringValue":"hello via collector"}}]}]}]}'
$body | Set-Content -Path "$env:TEMP\otlp-body.json" -Encoding UTF8 -NoNewline
docker run --rm --network=opentelemetry-demo -v "$env:TEMP\otlp-body.json:/data.json" curlimages/curl:latest -s -X POST -H "Content-Type: application/json" --data-binary "@/data.json" -w "collector:%{http_code}`n" http://otel-collector:4318/v1/logs
Start-Sleep -Seconds 3
docker exec loki-od wget -qO- "http://localhost:3100/metrics" 2>$null | Select-String "loki_distributor_lines_received_total\{|loki_ingester_streams_created_total\{"
