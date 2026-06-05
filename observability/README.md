# Observability

VictoriaMetrics als Prometheus-kompatible TSDB plus Standard-Scraper.

| Datei | Inhalt |
|---|---|
| `victoriametrics.yaml` | Single-Node VM Server, Scrape-Config, PVC (4Gi) |
| `kube-state-metrics.yaml` | Cluster-State Metriken |
| `node-exporter.yaml` | Host-Metriken (DaemonSet, `hostNetwork`/`hostPID`/`hostPath`) |
| `vmalert.yaml` | Alert-Regeln + Notifier |
| `k8up-schedule.yaml` | Restic Prune/Check für VM-Repo (Backups laufen über den Orchestrator in [../k8up/](../k8up/)) |

## Installation

```sh
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f victoriametrics.yaml
kubectl apply -f kube-state-metrics.yaml
kubectl apply -f node-exporter.yaml
kubectl apply -f vmalert.yaml
kubectl apply -f k8up-schedule.yaml
```

Grafana zeigt auf den ClusterIP-Service `victoriametrics.observability.svc:8428`.

## PodSecurity-Warnings

Beim Apply erscheinen Warnings (`warn: restricted`), aber kein Enforcement
blockt die Pods:

- `victoriametrics`: `data-perm` initContainer (root + `CHOWN/FOWNER/DAC_OVERRIDE`) — siehe [../k8up/README.md](../k8up/README.md#restore).
- `node-exporter`: `hostNetwork`, `hostPID`, hostPath-Volumes — unvermeidbar.

Kein Namespace-Label nötig — die Warnings sind kosmetisch.

## Daten-Backup

VM-Daten werden über [../k8up/](../k8up/) per restic nach B2 gesichert.
PVC: `victoriametrics-data`. Restore-Workflow siehe k8up README.
