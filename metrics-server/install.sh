#!/bin/bash
set -euo pipefail

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server

# --kubelet-insecure-tls required on Talos: metrics-server does not trust
# the Talos-generated kubelet serving certificates by default.
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args={--kubelet-insecure-tls}

kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s
echo "metrics-server installed successfully."
