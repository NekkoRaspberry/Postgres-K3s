#!/usr/bin/env bash
# Create a database + user for one app, and save the credentials
# as a Secret named "<app>-db" in the app's namespace.
# Usage: ./new-app-db.sh <app-name> <app-namespace>
set -euo pipefail

APP="${1:-}"
NS="${2:-}"
if [[ -z "$APP" || -z "$NS" ]]; then
  echo "Usage: $0 <app-name> <app-namespace>"
  exit 1
fi
# Lowercase letters and digits only (valid for both PostgreSQL and Kubernetes names)
if [[ ! "$APP" =~ ^[a-z][a-z0-9]*$ ]]; then
  echo "App name must be lowercase letters and digits, starting with a letter."
  exit 1
fi

# Random password, never printed
PASS="$(openssl rand -hex 24)"

# Create the user and its own database; other users cannot connect to it
kubectl exec -i -n databases postgres-0 -- psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE $APP LOGIN PASSWORD '$PASS';
CREATE DATABASE $APP OWNER $APP;
REVOKE ALL ON DATABASE $APP FROM PUBLIC;
SQL

# Save the connection details where the app can read them
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic "$APP-db" -n "$NS" \
  --from-literal=host=postgres.databases.svc.cluster.local \
  --from-literal=port=5432 \
  --from-literal=database="$APP" \
  --from-literal=username="$APP" \
  --from-literal=password="$PASS"

echo "Done: database '$APP', credentials in Secret '$APP-db' (namespace '$NS')."
