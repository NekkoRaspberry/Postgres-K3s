#!/usr/bin/env bash
# Restore one database from a .dump file. EXISTING DATA IN THAT DATABASE IS REPLACED.
# Usage: ./restore.sh <database> <file.dump> [--yes]
set -euo pipefail
# Use ~/.kube/config on the Pi; inside a pod (CI runner) kubectl uses the pod's own access
if [[ -z "${KUBECONFIG:-}" && -f "$HOME/.kube/config" ]]; then export KUBECONFIG="$HOME/.kube/config"; fi

DB="${1:-}"
FILE="${2:-}"
if [[ -z "$DB" || ! -f "$FILE" ]]; then
  echo "Usage: $0 <database> <file.dump> [--yes]"
  exit 1
fi

# Ask before overwriting, unless --yes was given
if [[ "${3:-}" != "--yes" ]]; then
  read -r -p "This replaces all data in '$DB'. Type the database name to confirm: " ANSWER
  [[ "$ANSWER" == "$DB" ]] || { echo "Cancelled."; exit 1; }
fi

# Create the database if it does not exist yet
EXISTS="$(kubectl exec -n databases postgres-0 -- psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'")"
if [[ "$EXISTS" != "1" ]]; then
  kubectl exec -n databases postgres-0 -- createdb -U postgres "$DB"
fi

# Restore in one transaction: if anything fails, nothing is changed
kubectl exec -i -n databases postgres-0 -- \
  pg_restore -U postgres --clean --if-exists --single-transaction -d "$DB" < "$FILE"

echo "Restored '$DB' from $FILE"
