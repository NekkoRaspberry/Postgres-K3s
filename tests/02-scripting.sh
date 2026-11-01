#!/usr/bin/env bash
# Does new-app-db.sh work, and are apps isolated from each other?
# Creates temporary databases/users and removes them at the end.
source "$(dirname "$0")/lib.sh"
echo "== 02 Scripting (new-app-db.sh)"

APP=pgtestapp
OTHER=pgtestother

cleanup() {
  psql_admin -c "DROP DATABASE IF EXISTS $APP" -c "DROP DATABASE IF EXISTS $OTHER" \
    -c "DROP ROLE IF EXISTS $APP" -c "DROP ROLE IF EXISTS $OTHER" >/dev/null 2>&1
  kubectl delete secret -n "$TEST_NS" "$APP-db" "$OTHER-db" --ignore-not-found >/dev/null 2>&1
}
trap cleanup EXIT
cleanup   # start from a clean state

check_fails "rejects missing arguments"  "$ROOT/new-app-db.sh"
check_fails "rejects invalid app name"   "$ROOT/new-app-db.sh" Bad-Name "$TEST_NS"
check "creates app database"             "$ROOT/new-app-db.sh" "$APP" "$TEST_NS"
check "creates second app database"      "$ROOT/new-app-db.sh" "$OTHER" "$TEST_NS"
check_fails "refuses to create the same app twice" "$ROOT/new-app-db.sh" "$APP" "$TEST_NS"

for KEY in host port database username password; do
  check "secret contains '$KEY'" \
    test -n "$(kubectl get secret -n "$TEST_NS" "$APP-db" -o jsonpath="{.data.$KEY}")"
done

PASS="$(kubectl get secret -n "$TEST_NS" "$APP-db" -o jsonpath='{.data.password}' | base64 -d)"

OUT="$(psql_remote "$APP" "$PASS" "$APP" "SELECT current_database()")"
check "app connects from another pod with its password" test "$OUT" = "$APP"

# psql prints one line per statement; the SELECT result is the last line
OUT="$(psql_remote "$APP" "$PASS" "$APP" "CREATE TABLE t (id int); INSERT INTO t VALUES (42); SELECT id FROM t" | tail -n 1)"
check "app can create tables and write data" test "$OUT" = 42

check_fails "wrong password is rejected"            psql_remote "$APP" wrongpassword "$APP" "SELECT 1"
check_fails "app cannot open another app's database" psql_remote "$APP" "$PASS" "$OTHER" "SELECT 1"

finish
