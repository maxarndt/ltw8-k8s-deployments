#!/bin/bash
set -euo pipefail

METALLB_VERSION="v0.14.9"

echo "Installing MetalLB ${METALLB_VERSION}..."
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

echo "Waiting for MetalLB controller to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=controller \
  --timeout=120s

echo "Waiting for MetalLB speaker to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb,component=speaker \
  --timeout=120s

echo "Applying IP address pool..."
kubectl apply -f ipaddresspool.yaml

echo "MetalLB installed successfully."
