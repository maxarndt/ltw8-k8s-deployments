# Local Path Provisioner

Dynamische PersistentVolumes auf dem Talos User Volume (`u-local-storage`,
gemountet unter `/var/mnt/local-storage` — konfiguriert in
[../talos/patches/volume-local-storage.yaml](../talos/patches/volume-local-storage.yaml)).

Ist die default StorageClass des Clusters; alle PVCs ohne explizite
`storageClassName` landen hier.

## Voraussetzung

Talos User Volume existiert:

```sh
talosctl get volumestatus u-local-storage
```

Erwartet: `phase: ready`, Mount unter `/var/mnt/local-storage`.

## Installation

```sh
kubectl kustomize . | kubectl apply -f -
```

## Verifizierung

```sh
kubectl get storageclass               # local-path (default)
kubectl get pod -n local-path-storage  # provisioner Ready
talosctl ls /var/mnt/local-storage     # PVC-Verzeichnisse nach erstem Claim
```

## Patches

Die Kustomization überschreibt am Upstream-Manifest:
- **Storage-Pfad**: `/var/mnt/local-storage` (Talos User Volume)
- **Default StorageClass**: `local-path`
- **Namespace-Label**: `pod-security.kubernetes.io/enforce: privileged` (Provisioner mountet hostPath)

## Deinstallation

```sh
kubectl kustomize . | kubectl delete -f -
```

PVCs/PVs vorher migrieren — sonst gehen die Daten verloren.
