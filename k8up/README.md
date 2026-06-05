# K8up Backup & Restore

K8up (https://k8up.io) is a Restic-based Kubernetes operator. On this
single-node Talos cluster it replaces the Velero install that didn't work
out — see "Why not Velero" below.

## Design

```
k8up-system
├── k8up operator
└── backup-orchestrator CronJob (daily 02:00 Europe/Berlin)
    │
    ├── scale grafana/grafana       → 0
    ├── scale observability/victoriametrics → 0
    ├── scale nats/nats             → 0
    ├── wait for pods to terminate (releases RWO PVCs)
    │
    ├── apply Backup CR in grafana       → k8up Job mounts grafana-data,         restic push → s3://ltw8-kubernetes-backup-01/grafana
    ├── apply Backup CR in observability → k8up Job mounts victoriametrics-data, restic push → s3://ltw8-kubernetes-backup-01/observability
    ├── apply Backup CR in nats          → k8up Job mounts nats-data,            restic push → s3://ltw8-kubernetes-backup-01/nats
    │
    └── trap EXIT: scale all Deployments back to 1
```

Each namespace has its own restic repository (one bucket sub-path per ns),
so restores are isolated. Per-namespace `Schedule` CRs (`*/k8up-schedule.yaml`)
handle weekly `prune` (retention enforcement) and monthly `check`
(repo integrity verification) — both run without quiesce since they only
touch the restic repo.

Retention: 7 daily, 4 weekly, 6 monthly snapshots per namespace.

## Install

```sh
cd k8up
./install.sh
```

The script:
1. Installs the K8up operator via Helm into `k8up-system`.
2. Prompts for Backblaze B2 keyID + applicationKey + restic repo password
   (or generates one) and creates a `k8up-backup-credentials` Secret in
   each of the 3 application namespaces.
3. Applies the orchestrator RBAC + CronJob and the per-namespace
   `Schedule`s.

**Save the restic repo password.** It's the only thing that can decrypt
the backups, and B2 doesn't have it.

## Verify

```sh
kubectl -n k8up-system get pods
kubectl get schedules -A
kubectl -n k8up-system get cronjob backup-orchestrator

# Trigger a one-off run:
kubectl -n k8up-system create job --from=cronjob/backup-orchestrator manual-test
kubectl get backups -A -w
kubectl -n k8up-system logs job/manual-test -f
```

Inspect the B2 bucket via the Backblaze UI — you should see
`ltw8-kubernetes-backup-01/<ns>/{config,keys,data,snapshots,index}` after the first
successful run.

## Restore

1. Pick the snapshot. List with the helper Job in
   [restore-job-template.yaml](restore-job-template.yaml) — edit
   `REPLACE_NAMESPACE`, apply, read logs:
   ```sh
   kubectl apply -f restore-job-template.yaml   # only the Job part
   kubectl -n <ns> logs job/list-snapshots
   ```
2. Scale the target Deployment to 0 and wait for the pod to release the RWO PVC:
   ```sh
   kubectl -n <ns> scale deployment/<name> --replicas=0
   kubectl -n <ns> wait --for=delete pod -l app=<name> --timeout=120s
   ```
3. Replace the PVC with an empty one. **Do not re-apply the full
   workload manifest** — it resets the Deployment to `replicas: 1`, and
   the pod will race the Restore Job onto the empty PVC. Instead apply
   only a standalone PVC manifest (same name/size/storageClass as the
   one in the workload), so no Pod gets scheduled:
   ```sh
   kubectl -n <ns> delete pvc <pvc-name>
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: <pvc-name>
     namespace: <ns>
   spec:
     accessModes: [ReadWriteOnce]
     storageClassName: local-path
     resources:
       requests:
         storage: <size>
   EOF
   ```
4. Apply a `Restore` CR — copy [restore-job-template.yaml](restore-job-template.yaml),
   fill the `REPLACE_*` placeholders, apply.
5. Wait, then scale back up:
   ```sh
   kubectl -n <ns> wait --for=condition=Completed restore/<name> --timeout=15m
   kubectl -n <ns> scale deployment/<name> --replicas=1
   ```

### Why the `data-perm` initContainer exists

k8up's restore Job runs as uid `65532` (distroless), so restored files
land owned by `65532:root` regardless of who the target workload runs
as. The `nats`, `grafana` and `victoriametrics` Deployments each have a
small root initContainer (`data-perm`) that `chown`s the PVC root to
the workload's UID before the main container starts. Idempotent — a
no-op on normal restarts.

## Troubleshooting

**Backup hangs with no pods**: the orchestrator probably can't release
the PVC because a stale pod isn't terminating. Check
`kubectl -n <ns> get pods` and force-delete if needed.

**`failed to acquire lock`** on prune: a previous prune job didn't release
its lock cleanly. Run `restic unlock` via a helper Job (use the
list-snapshots template, change command to `["restic", "unlock"]`).

**Operator pod CrashLoopBackOff** after Talos upgrade: K8up needs to
re-watch CRDs; deleting the operator pod usually fixes it.
`kubectl -n k8up-system delete pod -l app.kubernetes.io/name=k8up`.

**`Signature validation failed`** in a Backup/Restore/Schedule Pod:
B2 credentials in the namespace-local `k8up-backup-credentials` Secret
are wrong. `install.sh` creates the same Secret in all 3 namespaces in
one go — if you fix or rotate credentials, update **all 3 namespaces**,
otherwise the next backup/restore in the un-fixed namespace fails the
same way. Sanity check across namespaces:

```sh
for ns in nats grafana observability; do
  echo "--- $ns ---"
  for k in username password repo-password; do
    printf "%-15s " "$k"
    kubectl -n $ns get secret k8up-backup-credentials \
      -o jsonpath="{.data.$k}" | base64 -d | md5
  done
done
```

All three rows per field should hash identically.

## Why not Velero

Velero's file-system backup (Kopia/Restic via node-agent) needs a
DaemonSet that hostPath-mounts `/var/lib/kubelet/pods` and runs
privileged. Talos' default Pod Security Admission (`baseline`) blocks
this, and even with `privileged: true` the unusual kubelet layout
caused Kopia to fail to find pod volumes. K8up sidesteps this by
spawning per-PVC backup Pods that mount the PVC directly (RWO) —
no hostPath, no privileged, fully compatible with Talos baseline PSA.
