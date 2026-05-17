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
    ├── apply Backup CR in grafana       → k8up Job mounts grafana-data,         restic push → s3://ltw8-backup/grafana
    ├── apply Backup CR in observability → k8up Job mounts victoriametrics-data, restic push → s3://ltw8-backup/observability
    ├── apply Backup CR in nats          → k8up Job mounts nats-data,            restic push → s3://ltw8-backup/nats
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
`ltw8-backup/<ns>/{config,keys,data,snapshots,index}` after the first
successful run.

## Restore

1. Pick the snapshot. List with the helper Job in
   [restore-job-template.yaml](restore-job-template.yaml) — edit
   `REPLACE_NAMESPACE`, apply, read logs:
   ```sh
   kubectl apply -f restore-job-template.yaml   # only the Job part
   kubectl -n <ns> logs job/list-snapshots
   ```
2. Scale the target Deployment to 0:
   ```sh
   kubectl -n <ns> scale deployment/<name> --replicas=0
   ```
3. Clear the PVC (if you want a clean restore) and re-create it:
   ```sh
   kubectl -n <ns> delete pvc <pvc-name>
   kubectl apply -f ../<ns>/<workload>.yaml
   ```
4. Apply a `Restore` CR — copy [restore-job-template.yaml](restore-job-template.yaml),
   fill the `REPLACE_*` placeholders, apply.
5. Wait, then scale back up:
   ```sh
   kubectl -n <ns> wait --for=condition=Completed restore/<name> --timeout=15m
   kubectl -n <ns> scale deployment/<name> --replicas=1
   ```

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

## Why not Velero

Velero's file-system backup (Kopia/Restic via node-agent) needs a
DaemonSet that hostPath-mounts `/var/lib/kubelet/pods` and runs
privileged. Talos' default Pod Security Admission (`baseline`) blocks
this, and even with `privileged: true` the unusual kubelet layout
caused Kopia to fail to find pod volumes. K8up sidesteps this by
spawning per-PVC backup Pods that mount the PVC directly (RWO) —
no hostPath, no privileged, fully compatible with Talos baseline PSA.
