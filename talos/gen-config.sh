#!/usr/bin/env bash
# Generiert Talos Machine-Configs für den Cluster.
#
# Usage:
#   CLUSTER_NAME=ltw8-cluster NODE_IP=10.8.10.97 NODE_HOSTNAME=ltw8-cp-01 \
#     ./gen-config.sh
#
# Beim ersten Lauf wird secrets.yaml erzeugt (CA-Keys, encryption secret,
# admin client cert). Offline sichern — ohne sie ist der Cluster nicht
# wiederherstellbar. Spätere Läufe nutzen die vorhandene secrets.yaml,
# sodass die Cluster-Identität stabil bleibt.

set -euo pipefail
cd "$(dirname "$0")"

: "${CLUSTER_NAME:?set CLUSTER_NAME (z.B. ltw8-cluster)}"
: "${NODE_IP:?set NODE_IP (z.B. 10.8.10.97)}"
: "${NODE_HOSTNAME:?set NODE_HOSTNAME (z.B. ltw8-cp-01)}"

command -v talosctl >/dev/null || { echo "talosctl nicht im PATH"; exit 1; }
command -v yq       >/dev/null || { echo "yq nicht im PATH (brew install yq)"; exit 1; }

if [[ ! -f secrets.yaml ]]; then
  echo "Neue secrets.yaml wird erzeugt — offline sichern (Passwortmanager / Backblaze Vault)."
  talosctl gen secrets --output-file secrets.yaml
else
  echo "Bestehende secrets.yaml wiederverwendet."
fi

rm -rf generated
talosctl gen config "$CLUSTER_NAME" "https://${NODE_IP}:6443" \
  --with-secrets secrets.yaml \
  --output-dir generated \
  --config-patch @patches/controlplane.yaml \
  --config-patch @patches/volume-ephemeral.yaml \
  --config-patch @patches/volume-local-storage.yaml \
  --config-patch "machine:
  network:
    hostname: ${NODE_HOSTNAME}"

# talosctl gen config setzt auf CP-Nodes per Default
# node.kubernetes.io/exclude-from-external-load-balancers. MetalLB L2
# überspringt Nodes mit diesem Label — auf einem Single-Node-Cluster wird
# der LB-Pool dann nie announced. Siehe memory/project_metallb_talos_label.md.
yq -i 'del(.machine.nodeLabels."node.kubernetes.io/exclude-from-external-load-balancers")' \
  generated/controlplane.yaml

echo
echo "Generiert:"
ls -la generated/
echo
echo "Nächste Schritte:"
echo "  talosctl apply-config --insecure -n $NODE_IP -f generated/controlplane.yaml"
echo "  export TALOSCONFIG=$(pwd)/generated/talosconfig"
echo "  talosctl config endpoint $NODE_IP && talosctl config node $NODE_IP"
echo "  talosctl bootstrap"
echo "  talosctl kubeconfig --force ~/.kube/config"
