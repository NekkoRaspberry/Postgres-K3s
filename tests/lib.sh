# Shared helpers for the tests (loaded by each test file, not run directly)
# Use ~/.kube/config on the Pi; inside a pod (CI runner) kubectl uses the pod's own access
if [[ -z "${KUBECONFIG:-}" && -f "$HOME/.kube/config" ]]; then export KUBECONFIG="$HOME/.kube/config"; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS=databases
TEST_NS=pgtest          # namespace for test apps (permanent, emptied after each test)
FILES_POD=pgtest-files  # helper pod that reads the backup folder
FAILS=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
warn() { echo "  WARN  $1"; }

# check "<description>" <command...>  -> PASS if the command succeeds
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

# check_fails "<description>" <command...>  -> PASS if the command FAILS
check_fails() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$name"; else pass "$name"; fi
}

# Run SQL as admin inside the database pod
psql_admin() {
  kubectl exec -i -n "$NS" postgres-0 -- psql -U postgres -v ON_ERROR_STOP=1 -tA "$@"
}

# Run SQL from a separate pod, like a real app would (network + password).
# Usage: psql_remote <user> <password> <database> "<sql>"   -> prints output
psql_remote() {
  local pod="pgclient-$RANDOM" phase=""
  kubectl run "$pod" -n "$TEST_NS" --restart=Never --image=postgres:17-alpine \
    --env=PGPASSWORD="$2" -- \
    psql -h postgres.databases.svc.cluster.local -U "$1" -d "$3" -tAc "$4" >/dev/null
  for _ in $(seq 1 60); do
    phase="$(kubectl get pod -n "$TEST_NS" "$pod" -o jsonpath='{.status.phase}')"
    [[ "$phase" == Succeeded || "$phase" == Failed ]] && break
    sleep 2
  done
  kubectl logs -n "$TEST_NS" "$pod" 2>&1
  kubectl delete pod -n "$TEST_NS" "$pod" >/dev/null 2>&1
  [[ "$phase" == Succeeded ]]
}

# Backup files live on the Pi, so tests read them through a helper pod
# (works both on the Pi and from a CI runner pod).
files_pod_start() {
  local path
  path="$(kubectl get cronjob -n "$NS" postgres-backup \
    -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[?(@.name=="backup")].hostPath.path}')"
  kubectl run "$FILES_POD" -n "$NS" --restart=Never --image=postgres:17-alpine --overrides='{
    "spec": {
      "securityContext": {"runAsUser": 1000, "runAsGroup": 1000},
      "containers": [{
        "name": "files", "image": "postgres:17-alpine", "command": ["sleep", "600"],
        "volumeMounts": [{"name": "backup", "mountPath": "/backup"}]
      }],
      "volumes": [{"name": "backup", "hostPath": {"path": "'"$path"'", "type": "Directory"}}]
    }}' >/dev/null
  kubectl wait -n "$NS" --for=condition=Ready "pod/$FILES_POD" --timeout=90s >/dev/null
}
files_pod_stop() { kubectl delete pod -n "$NS" "$FILES_POD" --ignore-not-found --grace-period=1 >/dev/null 2>&1; }

# Run a shell command in the backup folder (/backup) through the helper pod
in_backup() { kubectl exec -n "$NS" "$FILES_POD" -- sh -c "cd /backup && $1"; }

# Print the result and exit with 0 (all good) or 1 (something failed)
finish() {
  if [[ "$FAILS" -eq 0 ]]; then echo "  -> all passed"; exit 0
  else echo "  -> $FAILS failed"; exit 1; fi
}
