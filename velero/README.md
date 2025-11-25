# Velero Backup Configuration

Dieses Verzeichnis enthält die Konfiguration für Velero mit File System Backup (FSB) und Backblaze B2 S3-kompatibler Storage.

## Features

- **File System Backup (FSB)**: Backup von Persistent Volumes via Kopia
- **Verschlüsselung**: Kopia Repository-Verschlüsselung at Rest
- **Backblaze B2**: S3-kompatible Object Storage
- **Automatische Schedules**: Tägliche Backups + wöchentlicher Full-Backup
- **30 Tage Retention**: Automatisches Löschen alter Backups

## Voraussetzungen

### 1. Backblaze B2 Account Setup

Folge diesen Schritten um einen Backblaze B2 Bucket zu erstellen:

1. **Account erstellen**: https://www.backblaze.com/b2/cloud-storage.html

2. **B2 Bucket erstellen**:
   ```
   - Gehe zu "Buckets" → "Create a Bucket"
   - Bucket Name: z.B. k8s-velero-backups
   - Files in Bucket: Private
   - Default Encryption: Disabled (Kopia verschlüsselt)
   - Object Lock: Disabled
   ```

3. **Application Key erstellen**:
   ```
   - Gehe zu "App Keys" → "Add a New Application Key"
   - Name: velero-backup-key
   - Allow access to Bucket(s): Wähle deinen Bucket
   - Type of Access: Read and Write
   - Allow List All Bucket Names: Optional
   ```

   Notiere:
   - **keyID** (z.B. `005abcdef1234567890`)
   - **applicationKey** (z.B. `K005abcdefghijklmnopqrstuvwxyz`)

4. **S3 Endpoint ermitteln**:
   - Format: `s3.{region}.backblazeb2.com`
   - Region steht in der Bucket-Übersicht (z.B. `us-west-004`, `eu-central-003`)
   - Beispiel: `s3.us-west-004.backblazeb2.com`

### 2. Velero CLI installieren

```bash
# macOS
brew install velero

# Verify
velero version --client-only
```

## Installation

### Schritt 1: values.yaml anpassen

Bearbeite `values.yaml` und trage ein:
- `bucket`: Dein Backblaze Bucket Name
- `region`: Deine Backblaze Region (z.B. `us-west-004`)
- `s3Url`: Dein S3 Endpoint (z.B. `https://s3.us-west-004.backblazeb2.com`)

### Schritt 2: Backblaze Credentials Secret erstellen

```bash
kubectl create namespace velero
kubectl label namespace velero pod-security.kubernetes.io/enforce=privileged --overwrite

kubectl create secret generic -n velero velero-backblaze-credentials \
  --from-literal=cloud="[default]
aws_access_key_id=YOUR_KEY_ID
aws_secret_access_key=YOUR_SECRET"
```

### Schritt 3: Velero installieren

```bash
./install.sh
```

Das Skript:
1. Erstellt das Kopia Verschlüsselungs-Passwort
2. Installiert Velero via Helm
3. Erstellt die Backup Schedules
4. Verifiziert die Installation

Erwartete Pods:
- `velero-xxx` - Velero Server
- `node-agent-xxx` - Node Agent DaemonSet

### Manuelle Installation

Falls du das Skript nicht nutzen möchtest:

```bash
# Helm Repository
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Kopia Encryption Password
kubectl create secret generic -n velero velero-repo-credentials \
  --from-literal=repository-password="$(openssl rand -base64 32)"

# Velero installieren
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --values values.yaml

# Backup Schedules
kubectl apply -f backup-schedule.yaml

# Verifizieren
kubectl get pods -n velero
kubectl get backupstoragelocation -n velero
kubectl get schedules -n velero
```

### Backup Schedules

- `observability-daily` - Täglich 02:00 Uhr
- `grafana-daily` - Täglich 02:15 Uhr
- `full-cluster-weekly` - Sonntags 03:00 Uhr

## Backup-Übersicht

### Was wird gesichert?

| Namespace | PVCs | Size | Backup Zeit |
|-----------|------|------|-------------|
| observability | victoriametrics-data | 4Gi | 02:00 |
| grafana | grafana-data | 1Gi | 02:15 |
| clima | keine | - | 02:30 |
| alle | alle | ~5Gi | So 03:00 |

### Backup-Strategie

- **Tägliche Backups**: Pro Namespace, 30 Tage Aufbewahrung
- **Wöchentlicher Full-Backup**: Kompletter Cluster, 90 Tage Aufbewahrung
- **File System Backup**: Alle PVCs werden via Kopia gesichert
- **Verschlüsselung**: Kopia Repository-Verschlüsselung aktiviert

## Verwendung

### Backup Status prüfen

```bash
# Alle Backups anzeigen
velero backup get

# Backup Details
velero backup describe observability-daily-20240101000000

# Backup Logs
velero backup logs observability-daily-20240101000000

# Backup Storage Location prüfen
velero backup-location get
```

### Manuelles Backup erstellen

```bash
# Einzelnes Namespace
velero backup create observability-manual \
  --include-namespaces observability \
  --default-volumes-to-fs-backup

# Kompletter Cluster
velero backup create full-manual \
  --exclude-namespaces velero \
  --default-volumes-to-fs-backup

# Backup Status verfolgen
velero backup describe observability-manual --details
```

### Restore durchführen

```bash
# Komplettes Namespace wiederherstellen
velero restore create --from-backup observability-daily-20240101000000

# Nur bestimmte PVC wiederherstellen
velero restore create --from-backup observability-daily-20240101000000 \
  --include-resources persistentvolumeclaims \
  --selector app=victoriametrics

# In anderes Namespace wiederherstellen
velero restore create --from-backup grafana-daily-20240101000000 \
  --namespace-mappings grafana:grafana-restored

# Restore Status prüfen
velero restore get
velero restore describe <restore-name>
```

### PVC nach Restore wieder mounten

Nach einem Restore musst du ggf. die Pods neu starten:

```bash
# Deployment neu starten
kubectl rollout restart deployment/victoriametrics -n observability
kubectl rollout restart deployment/grafana -n grafana

# Status prüfen
kubectl get pods -n observability
kubectl get pvc -n observability
```

## Troubleshooting

### Backup schlägt fehl

```bash
# Velero Server Logs
kubectl logs -n velero deployment/velero

# Node Agent Logs (auf bestimmtem Node)
kubectl logs -n velero -l name=node-agent

# Backup Logs
velero backup logs <backup-name>

# Storage Location Status
velero backup-location get
```

### Häufige Probleme

**Problem: BackupStorageLocation ist "Unavailable"**
```bash
# Prüfe S3 Credentials
kubectl get secret -n velero velero-backblaze-credentials -o yaml

# Teste Verbindung manuell
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  s3 ls s3://<bucket-name>/ \
  --endpoint-url https://s3.<region>.backblazeb2.com
```

**Problem: FSB schlägt fehl mit "node agent not ready"**
```bash
# Prüfe Node Agent Pods
kubectl get pods -n velero -l name=node-agent

# Prüfe Node Agent auf bestimmtem Node
kubectl get pods -n velero -o wide | grep node-agent
kubectl logs -n velero <node-agent-pod>
```

**Problem: Kopia encryption fehlt**
```bash
# Prüfe ob Secret existiert
kubectl get secret -n velero velero-repo-credentials

# Secret neu erstellen falls nötig
kubectl create secret generic -n velero velero-repo-credentials \
  --from-literal=repository-password="$(openssl rand -base64 32)"
```

### Backup Performance

Erwartete Backup-Dauer (5Gi total):
- **Erstes Backup**: 15-30 Minuten
- **Folge-Backups**: 5-15 Minuten (inkrementell)

## Monitoring

Velero exportiert Prometheus Metrics:
- `velero_backup_success_total`
- `velero_backup_failure_total`
- `velero_backup_duration_seconds`

Falls Prometheus Operator vorhanden, setze in `values.yaml`:
```yaml
metrics:
  serviceMonitor:
    enabled: true
```

## Kosten (Backblaze B2)

Geschätzte Kosten für 5GB Daten mit 30 Tagen Retention:
- **Storage**: $6/TB/Monat
- **Total: < $1/Monat**

## Sicherheit

### Best Practices

1. **Repository Password**: Speichere Kopia-Passwort sicher (ohne kannst du nicht restoren)
2. **Backup Testing**: Teste Restores regelmäßig
3. **Credentials Rotation**: Rotiere Backblaze Keys regelmäßig

### Credentials sicher speichern

Credentials werden als Kubernetes Secret gespeichert:

```bash
kubectl create secret generic -n velero velero-backblaze-credentials \
  --from-literal=cloud="[default]
aws_access_key_id=YOUR_KEY_ID
aws_secret_access_key=YOUR_SECRET"
```

Das Secret wird **nicht** in Git committet und existiert nur im Cluster.

## Updates

```bash
helm repo update
helm upgrade velero vmware-tanzu/velero -n velero -f values.yaml
```

## Weitere Ressourcen

- [Velero Docs](https://velero.io/docs/)
- [Backblaze B2 Docs](https://www.backblaze.com/b2/docs/)
