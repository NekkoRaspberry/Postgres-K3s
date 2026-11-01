#!/usr/bin/env bash
# Did the tests clean up after themselves? (run last)
source "$(dirname "$0")/lib.sh"
echo "== 99 Leftovers"

check "no test databases left" \
  test -z "$(psql_admin -c "SELECT datname FROM pg_database WHERE datname LIKE 'pgtest%'")"
check "no test users left" \
  test -z "$(psql_admin -c "SELECT rolname FROM pg_roles WHERE rolname LIKE 'pgtest%'")"
check "test namespace is empty (no secrets or pods)" \
  test -z "$(kubectl get secrets,pods -n "$TEST_NS" -o name 2>/dev/null)"
check "no test jobs/pods left" \
  test -z "$(kubectl get jobs,pods -n "$NS" -o name | grep -E 'postgres-backup-test-|pgtest-')"

trap files_pod_stop EXIT
files_pod_start
check_fails "no test backup folders left" in_backup "ls -d test_*"
check_fails "no unfinished backups left"  in_backup "ls -d *.partial"

finish
