# Setting up Clarivize demo



# Docker

## Add these to [.env](.env) file

```text
# Clarivize - docker container
CLARIVIZE_PORT=9876
CLARIVIZE_HOST=clarivize-od
CLARIVIZE_PIPELINE_ID=CL-1J8Q43RFLD
CLARIVIZE_COLLECTOR_ENDPOINT=http://${CLARIVIZE_HOST}:${CLARIVIZE_PORT}/clarivize/${CLARIVIZE_PIPELINE_ID}
CLARIVIZE_FORWARD_ENDPOINT=http://otel-collector-cvz:4328
```

## Add these to [docker-compose.yml](docker-compose.yml)

```yaml
  clarivize-data-init:
    image: alpine:3.20
    user: 0:0
    volumes:
      - clarivize-data:/app/data
    command: ["sh", "-c", "chown -R 584792:584792 /app/data"]

  clarivize:
    image: clvzdocker/clarivize:v1.0.9719
    container_name: clarivize-od
    entrypoint: ["dotnet", "clarivize.dll"]
    depends_on:
      clarivize-data-init:
        condition: service_completed_successfully
    labels:
      - "service.type=instrumentation"
    ports:
      - "${CLARIVIZE_PORT}:${CLARIVIZE_PORT}"
    volumes:
      - clarivize-data:/app/data
      - ./Clarivize/activation_key.json:/app/activation_key.json:ro
    environment:
      CVZ_DBTYPE: SQLite
      CVZ_CONN: Data Source=/app/data/Clarivize.db
      CLARIVIZE_COLLECTOR_ENDPOINT: ${CLARIVIZE_COLLECTOR_ENDPOINT}
      CVZ_PIPELINE_ID: ${CLARIVIZE_PIPELINE_ID}
      CVZ_PIPELINE_PROVIDER_TYPE: otlp
      CVZ_PROVIDER_TARGET: ${CLARIVIZE_FORWARD_ENDPOINT}
      CVZ_ACTIVATION_KEY: /app/activation_key.json
```

## Activation key

    Store the JSON activation key in [Clarivize/activation_key.json](Clarivize/activation_key.json). It is mounted read-only at `/app/activation_key.json`.

```json
{
  "Licensee": "demo@clarivize.io",
  "Product": "Clarivize:EarlyPilot,DataReduction,SingleNode,AnomalyDetection,UsageReporting",
  "ExpirationDateUTC": "2027-08-12T17:22:43.830882Z",
  "Salt": "d29e59b92dd0",
  "Hash": "Cpll\u002B31lAcbK5E0MoOHlg8PhED1C4NKItKbFsy/Iy74=",
  "Signature": "r7RsY8lNLlviD4oZ7lItG58uAQyfHQrI4Zs/MOiU/qRvdIPjYxIU7VB/CU2mrsLnztcc5ztSBpYq9gFgfQKxbq5yWkeZivflpo0n8uod5hAUZCU50aV62\u002BF3xhoDBR2b3qYwLZHz8OFZ\u002Bokcp/jE3UFgfLfXUjGl/TzrVTZRrPOCyXmedUW07A1lUe0r5e3jIQ2nsm2uTlQ6ygl/LuoHfym3asKHvyc9eYYz9OE\u002B7kSvuW8\u002BoA7w2AZYVFMEO7ghOOoTk1t19/Hrb/Ro6qm9pu\u002BHLvzLtapklGbOIET9YhKhayeexXObh/IUtU7KrpHu9FhtypAcgwk\u002BN5yYMonu4Q=="
}
```