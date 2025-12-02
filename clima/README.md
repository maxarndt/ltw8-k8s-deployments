# LTW8 Clima OTEL Ingest

Wombat Pipelines zum Ingestieren von LTW8 Klima-Daten (Temperatur und Luftfeuchtigkeit) via NATS JetStream nach VictoriaMetrics.

## Lokale Ausführung

```bash
export NATS_CREDS_FILE="/path/to/your/credentials.creds"

# Temperatur-Pipeline
wombat run ltw8_temperature.yaml

# Luftfeuchtigkeit-Pipeline
wombat run ltw8_humidity.yaml
```

## Kubernetes Deployment

### Secret erstellen

```bash
kubectl create secret generic nats --from-file=creds=/path/to/credentials.creds -n clima
```

### ConfigMaps erstellen

```bash
# Temperatur-Pipeline
kubectl create configmap ltw8-temperature-config --from-file=ltw8_temperature.yaml -n clima

# Luftfeuchtigkeit-Pipeline
kubectl create configmap ltw8-humidity-config --from-file=ltw8_humidity.yaml -n clima
```

### ConfigMaps aktualisieren

```bash
# Temperatur-Pipeline
kubectl create configmap ltw8-temperature-config \
  --from-file=ltw8_temperature.yaml \
  --dry-run=client -o yaml -n clima | kubectl apply -f -

# Luftfeuchtigkeit-Pipeline
kubectl create configmap ltw8-humidity-config \
  --from-file=ltw8_humidity.yaml \
  --dry-run=client -o yaml -n clima | kubectl apply -f -
```

### Deployment anwenden

```bash
kubectl apply -f deployment.yaml
```

## Tests ausführen

```bash
# Temperatur-Pipeline testen
wombat test ltw8_temperature_benthos_test.yaml

# Luftfeuchtigkeit-Pipeline testen
wombat test ltw8_humidity_benthos_test.yaml
```
