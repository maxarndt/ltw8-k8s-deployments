#!/bin/bash
set -euo pipefail

echo "Adding Traefik Helm repo..."
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

echo "Creating traefik namespace..."
kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -

echo "Installing/upgrading Traefik..."
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --values values.yaml \
  --wait

echo "Traefik installed successfully."
kubectl get svc -n traefik traefik
