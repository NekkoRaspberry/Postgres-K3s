#!/usr/bin/env bash
# Are the files valid, does the cluster match them, and does data survive a restart?
# NOTE: restarts the PostgreSQL pod -> apps lose the database for ~10-30 seconds.
source "$(dirname "$0")/lib.sh"
echo "== 03 Deploying"

DB=pgtestpersist
cleanup() { psql_admin -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1; }
trap cleanup EXIT

MANIFESTS=(-f "$ROOT/postgres.yaml" -f "$ROOT/backup/cronjob.yaml")

check "manifests are valid (server dry-run)" kubectl apply --dry-run=server "${MANIFESTS[@]}"
# kubectl diff returns 0 when the cluster matches the files exactly
check "cluster matches the files (no drift)" kubectl diff "${MANIFESTS[@]}"

for SCRIPT in "$ROOT"/new-app-db.sh "$ROOT"/backup/*.sh; do
  check "script syntax OK: ${SCRIPT#$ROOT/}" bash -n "$SCRIPT"
done

# Persistence: write data, delete the pod, check the data is still there
cleanup
psql_admin -c "CREATE DATABASE $DB" >/dev/null
psql_admin -d "$DB" -c "CREATE TABLE t (v text); INSERT INTO t VALUES ('survived')" >/dev/null

echo "  ...restarting postgres-0"
kubectl delete pod -n "$NS" postgres-0 >/dev/null
check "pod comes back Ready after restart" \
  kubectl wait -n "$NS" --for=condition=Ready pod/postgres-0 --timeout=180s
check "data survives a pod restart" \
  test "$(psql_admin -d "$DB" -c 'SELECT v FROM t')" = survived

finish
