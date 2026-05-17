#!/bin/bash
set -euo pipefail

# K8up Installation Script
#
# 1. Installs the K8up operator into the k8up-system namespace.
# 2. Creates per-namespace credential secrets used by Backup, Schedule and
#    Restore CRs in grafana, observability and nats.
# 3. Applies the orchestrator RBAC + CronJob and the per-namespace Schedules
#    (prune + check).

NAMESPACES=(grafana observability nats)
SECRET_NAME=k8up-backup-credentials
B2_ENDPOINT="https://s3.eu-central-003.backblazeb2.com"
# Keep this in sync with the chart version pulled by `helm install` below.
K8UP_CRD_VERSION=k8up-4.9.0

command -v kubectl >/dev/null || { echo "ERROR: kubectl not found"; exit 1; }
command -v helm    >/dev/null || { echo "ERROR: helm not found"; exit 1; }
kubectl cluster-info >/dev/null || { echo "ERROR: cluster unreachable"; exit 1; }

echo "Step 1: Adding Helm repository..."
helm repo add k8up-io https://k8up-io.github.io/k8up
helm repo update

echo "Step 2: Applying namespace and CRDs..."
kubectl apply -f namespace.yaml
# The k8up Helm chart (v4+) does NOT ship CRDs — they must be applied
# separately before the operator install.
kubectl apply --server-side \
  -f "https://github.com/k8up-io/k8up/releases/download/${K8UP_CRD_VERSION}/k8up-crd.yaml"

echo "Step 3: Installing/upgrading K8up operator..."
helm upgrade --install k8up k8up-io/k8up \
  --namespace k8up-system \
  --values values.yaml \
  --wait \
  --timeout 5m

kubectl rollout status -n k8up-system deployment/k8up --timeout=180s

echo "Step 4: Creating per-namespace credential secrets..."
read -rp "Backblaze keyID (applicationKeyId): " B2_KEY_ID
read -rsp "Backblaze applicationKey: " B2_APP_KEY; echo
read -rsp "Restic repo password (leave blank to generate): " REPO_PW; echo
if [[ -z "${REPO_PW}" ]]; then
  REPO_PW=$(openssl rand -base64 32)
  echo "================================================"
  echo "Generated restic repo password — SAVE THIS:"
  echo "  ${REPO_PW}"
  echo "================================================"
  read -rp "Press Enter once saved..." _
fi

for ns in "${NAMESPACES[@]}"; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic "${SECRET_NAME}" \
    --namespace "${ns}" \
    --from-literal=username="${B2_KEY_ID}" \
    --from-literal=password="${B2_APP_KEY}" \
    --from-literal=repo-password="${REPO_PW}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo "Step 5: Applying orchestrator RBAC + CronJob..."
kubectl apply -f orchestrator-rbac.yaml
kubectl apply -f orchestrator-cronjob.yaml

echo "Step 6: Applying per-namespace Schedules (prune + check)..."
kubectl apply -f ../grafana/k8up-schedule.yaml
kubectl apply -f ../observability/k8up-schedule.yaml
kubectl apply -f ../nats/k8up-schedule.yaml

echo
echo "================================================"
echo "K8up installation complete."
echo "================================================"
echo
echo "Verify:"
echo "  kubectl -n k8up-system get pods"
echo "  kubectl get schedules -A"
echo "  kubectl -n k8up-system get cronjob backup-orchestrator"
echo
echo "Trigger a manual backup run:"
echo "  kubectl -n k8up-system create job --from=cronjob/backup-orchestrator manual-test"
echo "  kubectl get backups -A -w"
