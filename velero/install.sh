#!/bin/bash
set -e

echo "================================================"
echo "Velero Installation Script"
echo "================================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm not found. Please install helm first."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster."
    exit 1
fi

echo "Prerequisites check: OK"
echo ""

# Check if values.yaml has been configured
if grep -q "<YOUR_BUCKET_NAME>" values.yaml; then
    echo "ERROR: values.yaml contains placeholder values!"
    echo "Please edit values.yaml and replace:"
    echo "  - <YOUR_BUCKET_NAME>"
    echo "  - <YOUR_REGION>"
    echo "  - <YOUR_S3_ENDPOINT>"
    exit 1
fi

echo "Step 1: Adding Helm repository..."
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
echo ""

echo "Step 2: Creating velero namespace..."
kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -
echo ""

echo "Step 3: Checking Backblaze S3 credentials secret..."
if ! kubectl get secret -n velero velero-backblaze-credentials &> /dev/null; then
    echo "ERROR: Secret velero-backblaze-credentials not found!"
    echo ""
    echo "Please create the secret first with your Backblaze credentials:"
    echo ""
    echo "kubectl create secret generic -n velero velero-backblaze-credentials \\"
    echo "  --from-literal=cloud=\"[default]"
    echo "aws_access_key_id=YOUR_KEY_ID"
    echo "aws_secret_access_key=YOUR_SECRET\""
    echo ""
    echo "See README.md for detailed instructions."
    exit 1
else
    echo "Backblaze credentials secret found."
fi
echo ""

echo "Step 4: Creating Kopia repository encryption password..."
if kubectl get secret -n velero velero-repo-credentials &> /dev/null; then
    echo "Secret velero-repo-credentials already exists."
    read -p "Do you want to recreate it? (yes/no): " recreate
    if [ "$recreate" == "yes" ]; then
        kubectl delete secret -n velero velero-repo-credentials
        PASSWORD=$(openssl rand -base64 32)
        kubectl create secret generic -n velero velero-repo-credentials \
            --from-literal=repository-password="$PASSWORD"
        echo ""
        echo "================================================"
        echo "IMPORTANT: Save this password securely!"
        echo "Repository Password: $PASSWORD"
        echo "================================================"
        echo ""
        echo "Press Enter to continue..."
        read
    fi
else
    PASSWORD=$(openssl rand -base64 32)
    kubectl create secret generic -n velero velero-repo-credentials \
        --from-literal=repository-password="$PASSWORD"
    echo ""
    echo "================================================"
    echo "IMPORTANT: Save this password securely!"
    echo "Repository Password: $PASSWORD"
    echo "================================================"
    echo ""
    echo "Press Enter to continue..."
    read
fi

echo "Step 5: Installing Velero with Helm..."
helm upgrade --install velero vmware-tanzu/velero \
    --namespace velero \
    --values values.yaml \
    --wait \
    --timeout 10m
echo ""

echo "Step 6: Waiting for Velero to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/velero -n velero
echo ""

echo "Step 7: Verifying node-agent DaemonSet..."
kubectl rollout status daemonset/node-agent -n velero --timeout=300s
echo ""

echo "Step 8: Checking BackupStorageLocation..."
kubectl get backupstoragelocation -n velero
echo ""

echo "Waiting for BackupStorageLocation to sync..."
sleep 10

BSL_STATUS=$(kubectl get backupstoragelocation default -n velero -o jsonpath='{.status.phase}')
if [ "$BSL_STATUS" != "Available" ]; then
    echo "WARNING: BackupStorageLocation status is: $BSL_STATUS"
    echo "Check with: velero backup-location get"
    echo ""
fi

echo "Step 9: Creating backup schedules..."
kubectl apply -f backup-schedule.yaml
echo ""

echo "Step 10: Verifying schedules..."
kubectl get schedules -n velero
echo ""

echo "================================================"
echo "Velero Installation Complete!"
echo "================================================"
echo ""
echo "Verify installation:"
echo "  kubectl get pods -n velero"
echo "  kubectl get backupstoragelocation -n velero"
echo "  kubectl get schedules -n velero"
echo ""
echo "Install Velero CLI:"
echo "  brew install velero"
echo ""
echo "Create test backup:"
echo "  velero backup create test --include-namespaces observability"
echo "  velero backup describe test"
echo ""
