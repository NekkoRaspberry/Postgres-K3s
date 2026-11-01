# Postgres-K3s

One shared PostgreSQL 17 instance on K3s. Each application gets its own database and user.

## Overview

| Item | Value |
|---|---|
| Namespace | `databases` |
| Image | `postgres:17-alpine` |
| Address (inside the cluster) | `postgres.databases.svc.cluster.local:5432` |
| Exposure | ClusterIP only |
| Storage | 5 Gi, `local-path` |
| Memory limit | 512 Mi |
| Admin password | Secret `postgres-admin` |

## Files

| File | Purpose |
|---|---|
| `postgres.yaml` | Namespace, service and database |
| `new-app-db.sh` | Creates a database + user for one app |
| `backup/` | Nightly backup CronJob, `backup-now.sh`, `restore.sh` |
| `tests/` | Health, scripting, deploy and backup tests |
| `ci/` | Runner access and runner set for GitHub Actions |
| `.github/workflows/tests.yml` | Runs the tests on push to `main` and `dev` |

## Install

```bash
export KUBECONFIG=~/.kube/config
kubectl create namespace databases
kubectl create secret generic postgres-admin -n databases \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 24)"   # secret before the database
kubectl apply -f postgres.yaml
kubectl apply -f backup/cronjob.yaml
```

## Add a database for a new app

```bash
./new-app-db.sh <app-name> <app-namespace>
# example: ./new-app-db.sh nextcloud nextcloud
```

Creates a user and database named `<app-name>`, and a Secret `<app-name>-db` in the app's namespace with `host`, `port`, `database`, `username` and `password`.

```yaml
env:
  - name: DB_HOST
    valueFrom: { secretKeyRef: { name: nextcloud-db, key: host } }
  - name: DB_PASSWORD
    valueFrom: { secretKeyRef: { name: nextcloud-db, key: password } }
```

## Useful commands

```bash
kubectl get pods,pvc -n databases                                 # status
kubectl logs -n databases postgres-0 --tail=50                    # logs
kubectl exec -it -n databases postgres-0 -- psql -U postgres      # admin shell
kubectl exec -n databases postgres-0 -- psql -U postgres -c '\l'  # list databases
```

## Backup

Daily at 03:00 into `backup/data/<date>/` (one folder per day, kept 7 days). A missed backup runs when the Pi starts again.
- `globals.sql`: users
- `<database>.dump`: one file per database

```bash
./backup/backup-now.sh                                   # back up now
./backup/restore.sh <db> backup/data/<date>/<db>.dump    # restore one database
kubectl get cronjob,jobs -n databases                    # backup status
```

Full restore: users first, then each database.
```bash
kubectl exec -i -n databases postgres-0 -- psql -U postgres < backup/data/<date>/globals.sql
./backup/restore.sh <db> backup/data/<date>/<db>.dump
```

Destination folder: `hostPath.path` in `backup/cronjob.yaml`.

## Tests

```bash
./tests/run-all.sh               # all tests
./tests/run-all.sh --no-restart  # skip 03 (restarts the database)
```

| Test | Checks |
|---|---|
| `01-running.sh` | Pod, storage, service, version, memory and disk |
| `02-scripting.sh` | `new-app-db.sh`, passwords, app isolation |
| `03-deploying.sh` | Manifests valid, no drift, data survives a restart |
| `04-backup.sh` | Backup, file permissions, real backups untouched, restore |
| `99-leftovers.sh` | Nothing left behind by the tests |

### CI (GitHub Actions)

`.github/workflows/tests.yml` runs the tests (without 03) on every push to `main` and `dev`, on the `postgres-runners` runner set.

```bash
kubectl apply -f ci/test-runner-permissions.yaml   # runner account, its permissions, test namespace pgtest
helm install postgres-runners -n arc-runners -f ci/test-runner-helm-values.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --version 0.15.1
```

## Notes

- Deleting the `databases` namespace deletes all data.
