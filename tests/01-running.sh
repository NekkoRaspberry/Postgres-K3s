#!/usr/bin/env bash
# Is PostgreSQL running and healthy? (read-only, changes nothing)
source "$(dirname "$0")/lib.sh"
echo "== 01 Running"

check "pod postgres-0 is Ready" \
  kubectl wait -n "$NS" --for=condition=Ready pod/postgres-0 --timeout=10s
check "storage (PVC) is Bound" \
  test "$(kubectl get pvc -n "$NS" data-postgres-0 -o jsonpath='{.status.phase}')" = Bound
check "service has an endpoint" \
  test -n "$(kubectl get endpointslice -n "$NS" -l kubernetes.io/service-name=postgres -o jsonpath='{.items[*].endpoints[*].addresses[*]}')"
check "service is internal only (ClusterIP)" \
  test "$(kubectl get svc -n "$NS" postgres -o jsonpath='{.spec.type}')" = ClusterIP
check "admin secret exists" \
  kubectl get secret -n "$NS" postgres-admin
check "accepts connections (pg_isready)" \
  kubectl exec -n "$NS" postgres-0 -- pg_isready -U postgres
check "PostgreSQL version is 17" \
  test "$(psql_admin -c 'SHOW server_version_num' | cut -c1-2)" = 17

# Restarts are not always errors (e.g. after a reboot), so only warn
RESTARTS="$(kubectl get pod -n "$NS" postgres-0 -o jsonpath='{.status.containerStatuses[0].restartCount}')"
if [[ "$RESTARTS" -eq 0 ]]; then pass "no container restarts"; else warn "container restarted $RESTARTS time(s): check 'kubectl logs -n $NS postgres-0 --previous'"; fi

# Memory: below 80% of the 512Mi limit
MEM="$(kubectl top pod -n "$NS" postgres-0 --no-headers 2>/dev/null | awk '{print $3}' | tr -d 'Mi')"
if [[ -z "$MEM" ]]; then warn "memory usage unknown (metrics not ready yet)"
elif [[ "$MEM" -lt 410 ]]; then pass "memory usage ${MEM}Mi (< 80% of limit)"
else fail "memory usage ${MEM}Mi (>= 80% of 512Mi limit)"; fi

# Disk: data volume below 80% full
DISK="$(kubectl exec -n "$NS" postgres-0 -- df -P /var/lib/postgresql/data | awk 'NR==2 {print $5}' | tr -d '%')"
if [[ "$DISK" -lt 80 ]]; then pass "data disk ${DISK}% used"; else fail "data disk ${DISK}% used (>= 80%)"; fi

finish
