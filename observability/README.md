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

`node-exporter.yaml` legt den Namespace `observability` mit `pod-security.kubernetes.io/enforce=privileged` an (siehe Hinweis unten). Daher zuerst applyen, dann die anderen:

```sh
kubectl apply -f node-exporter.yaml
kubectl apply -f victoriametrics.yaml
kubectl apply -f kube-state-metrics.yaml
kubectl apply -f vmalert.yaml
kubectl apply -f k8up-schedule.yaml
```

Grafana zeigt auf den ClusterIP-Service `victoriametrics.observability.svc:8428`.

## PodSecurity

`victoriametrics`, `kube-state-metrics` und `vmalert` würden auch unter
`baseline` laufen (die `data-perm` initContainer-Capabilities werden von
`baseline` erlaubt, nur von `restricted` blockiert). **`node-exporter`
braucht aber Host-Zugriff** (`hostNetwork`/`hostPID`/`hostPort`/hostPath),
was `baseline` enforced. Deshalb der Namespace-weite `privileged` Label.

Wenn nach `kubectl apply` `kubectl -n observability get ds node-exporter`
`READY 0/1` zeigt und `describe ds node-exporter` ein `FailedCreate` mit
`violates PodSecurity baseline:latest` listet, fehlt das Label.

## Daten-Backup

VM-Daten werden über [../k8up/](../k8up/) per restic nach B2 gesichert.
PVC: `victoriametrics-data`. Restore-Workflow siehe k8up README.
