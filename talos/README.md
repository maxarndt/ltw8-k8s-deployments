# Talos Setup

Single-Node Talos Cluster (Controlplane + Workloads auf demselben Node).

## Inhalt

| Datei | Zweck |
|---|---|
| `gen-config.sh` | Erzeugt `secrets.yaml` (einmalig) + `generated/{controlplane,worker,talosconfig}` |
| `patches/controlplane.yaml` | Cluster-weite Settings (Scheduling auf CP erlauben) |
| `patches/volume-ephemeral.yaml` | EPHEMERAL-Partition (System `/var`) auf 30 GiB begrenzen |
| `patches/volume-local-storage.yaml` | User Volume für [../local-path/](../local-path/) als Backing-Store |
| `secrets.yaml` (gitignored) | CA-Keys, encryption secret, admin cert — **offline sichern** |
| `generated/` (gitignored) | Vollständige Machine-Configs, enthält alle Secrets |

## Voraussetzungen

- `talosctl`, `yq` (`brew install siderolabs/tap/talosctl yq`)
- Talos Image für die Zielhardware (siehe https://factory.talos.dev/ für
  Custom Images mit Extensions, z.B. für QEMU-Guest-Agent oder iscsi-tools)
- Node bootet von dem Image, IP per DHCP-Reservation in Unifi
  (10.8.10.0/24, fester Hostname)

## Cluster bauen

### 1. Configs generieren

```sh
CLUSTER_NAME=ltw8-cluster \
NODE_IP=10.8.10.97 \
NODE_HOSTNAME=ltw8-cp-01 \
./gen-config.sh
```

Beim ersten Lauf entsteht `secrets.yaml`. **Sofort offline sichern** (Passwortmanager-Attachment / Backblaze Vault). Geht sie verloren, ist der Cluster nicht mehr verwaltbar.

### 2. Node provisionieren

```sh
talosctl apply-config --insecure -n $NODE_IP -f generated/controlplane.yaml
```

Talos partitioniert die Disk, installiert sich, rebootet. Dauer ~3-5 min.

### 3. Cluster bootstrappen

```sh
export TALOSCONFIG=$(pwd)/generated/talosconfig
talosctl config endpoint $NODE_IP
talosctl config node $NODE_IP
talosctl health --wait-timeout 10m
talosctl bootstrap   # nur einmalig
talosctl kubeconfig --force ~/.kube/config
kubectl get nodes    # Ready erwartet
```

### 4. Cluster-Apps deployen

In dieser Reihenfolge:

```sh
# Storage zuerst (sonst hängen PVCs)
kubectl kustomize ../local-path | kubectl apply -f -

# Load Balancer + Ingress
kubectl apply -k ../metallb
kubectl apply -k ../traefik   # oder helm — je nach Verzeichnis

# Cert-Verwaltung, Backup, dann die Apps
kubectl apply -k ../cert-manager
./../k8up/install.sh
# ... grafana, observability, nats, clima
```

## Updates

- **Talos-Version upgraden**: `talosctl upgrade --image ghcr.io/siderolabs/installer:vX.Y.Z`
- **Patch ändern**: `gen-config.sh` neu laufen lassen, dann
  `talosctl apply-config -n $NODE_IP -f generated/controlplane.yaml` (ohne `--insecure`)
- **System-Volumes** (`VolumeConfig`, z.B. EPHEMERAL): wirken nur bei
  Erstinstallation. Änderung erfordert Wipe.
- **User-Volumes** (`UserVolumeConfig`, z.B. local-storage): runtime-managed.
  Können vergrößert werden (Patch ändern → `gen-config.sh` → `apply-config`).
  Shrinken wird nicht unterstützt. Mit `grow: true` füllt das Volume
  automatisch verfügbaren Platz auf der Disk auf.

## MetalLB-Gotcha (auto-handled)

`talosctl gen config` setzt auf CP-Nodes per Default das Label
`node.kubernetes.io/exclude-from-external-load-balancers`. MetalLB L2
überspringt Nodes mit diesem Label — auf einem Single-Node-Cluster wird
der LB-Pool dann nie announced. `gen-config.sh` entfernt das Label
automatisch. Bei manuellem `talosctl gen config` daran denken.

## Troubleshooting

**Disk wird falsch erkannt**: `talosctl get disks` — falls nicht
`system_disk` selektiert werden soll, in `patches/volume-*.yaml` z.B.
`busPath` oder `model` als Selektor nutzen
(https://www.talos.dev/latest/reference/configuration/block/volumeconfig/).

**Bootstrap hängt**: `talosctl logs etcd` und `talosctl dmesg`. Auf RPi
früher häufig Disk-Performance — neue Hardware sollte das nicht haben.

**Cert läuft ab**: Talos-Zertifikate haben 1 Jahr Laufzeit, werden aber
automatisch erneuert solange `talosctl health` grün ist. Aktuellen Stand
mit `talosctl get certs` prüfen.
