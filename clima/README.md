# LTW8 Clima OTEL Ingest

Wombat Pipeline zum Ingestieren von LTW8 Temperaturdaten via NATS JetStream nach VictoriaMetrics.

## Lokale Ausführung

```bash
export NATS_CREDS_FILE="/path/to/your/credentials.creds"
wombat run ltw8_temperature.yaml
```

## Kubernetes Deployment

### Secret erstellen

```bash
kubectl create secret generic nats --from-file=creds=/path/to/credentials.creds
```

### ConfigMap erstellen

```bash
kubectl create configmap ltw8-temperature-config --from-file=ltw8_temperature.yaml
```

### ConfigMap aktualisieren

```bash
kubectl create configmap ltw8-temperature-config \
  --from-file=ltw8_temperature.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Deployment anwenden

```bash
kubectl apply -f deployment.yaml
```
