#!/usr/bin/env bash
# Run a backup immediately (same job as the nightly CronJob) and show the result.
# Usage: ./backup-now.sh          (real backup, replaces today's)
#        ./backup-now.sh --test   (used by the tests: separate test_ folder)
set -euo pipefail
# Use ~/.kube/config on the Pi; inside a pod (CI runner) kubectl uses the pod's own access
if [[ -z "${KUBECONFIG:-}" && -f "$HOME/.kube/config" ]]; then export KUBECONFIG="$HOME/.kube/config"; fi

PREFIX=postgres-backup-manual
[[ "${1:-}" == "--test" ]] && PREFIX=postgres-backup-test
JOB="$PREFIX-$(date +%Y%m%d%H%M%S)"
kubectl create job -n databases --from=cronjob/postgres-backup "$JOB" >/dev/null
echo "Started $JOB, waiting..."

# Wait until the job is Complete or Failed (max 5 minutes)
STATUS=""
for _ in $(seq 1 150); do
  STATUS="$(kubectl get job -n databases "$JOB" -o jsonpath='{.status.conditions[?(@.status=="True")].type}')"
  [[ "$STATUS" == *Complete* || "$STATUS" == *Failed* ]] && break
  sleep 2
done

kubectl logs -n databases "job/$JOB"
if [[ "$STATUS" == *Complete* ]]; then
  echo "Backup succeeded."
else
  echo "Backup FAILED (status: $STATUS)."
  exit 1
fi
