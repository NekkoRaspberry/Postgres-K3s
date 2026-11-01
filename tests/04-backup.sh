#!/usr/bin/env bash
# Does a backup really work? Backup -> lose data -> restore -> data is back.
# The test backup goes to its own test_ folder (never replaces a real backup)
# and is deleted at the end, together with its job.
source "$(dirname "$0")/lib.sh"
echo "== 04 Backup & restore"

DB=pgtestbackup
TMP="$(mktemp -d)"   # local copy of the dump for restore.sh

cleanup() {
  psql_admin -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1
  in_backup "rm -rf test_*" >/dev/null 2>&1
  kubectl get jobs -n "$NS" -o name | grep '/postgres-backup-test-' \
    | xargs -r kubectl delete -n "$NS" --cascade=foreground >/dev/null 2>&1
  rm -rf "$TMP"
}
trap 'cleanup; files_pod_stop' EXIT
files_pod_start
cleanup
mkdir -p "$TMP"

# Fingerprint of all real backups, to prove the test does not change them
real_backups() { in_backup "find . -path './test_*' -prune -o -type f -print | sort | xargs -r md5sum"; }
BEFORE="$(real_backups)"

check "backup CronJob exists" kubectl get cronjob -n "$NS" postgres-backup

# Test data
psql_admin -c "CREATE DATABASE $DB" >/dev/null
psql_admin -d "$DB" -c "CREATE TABLE t (v text); INSERT INTO t VALUES ('precious')" >/dev/null

check "test backup job succeeds" "$ROOT/backup/backup-now.sh" --test

TESTDIR="$(in_backup "ls -1d test_* 2>/dev/null | grep -v '\.partial' | tail -n 1")"
check "test backup folder created" test -n "$TESTDIR"
check "globals.sql (users) is not empty" in_backup "test -s $TESTDIR/globals.sql"
check "test database dump is not empty"  in_backup "test -s $TESTDIR/$DB.dump"
check "backup files are private (owner only)" \
  test "$(in_backup "stat -c %a $TESTDIR/$DB.dump")" = 600
check_fails "no unfinished (.partial) backups left" in_backup "ls -d *.partial"
check "real backups were not changed" test "$(real_backups)" = "$BEFORE"

# Copy the dump out of the backup folder for restore.sh
in_backup "cat $TESTDIR/$DB.dump" > "$TMP/$DB.dump"

# Simulate data loss, then restore
psql_admin -d "$DB" -c "DROP TABLE t" >/dev/null
check "restore.sh runs" "$ROOT/backup/restore.sh" "$DB" "$TMP/$DB.dump" --yes
check "restored data is correct" \
  test "$(psql_admin -d "$DB" -c 'SELECT v FROM t')" = precious

# Full disaster: database deleted completely
psql_admin -c "DROP DATABASE $DB" >/dev/null
check "restore recreates a deleted database" "$ROOT/backup/restore.sh" "$DB" "$TMP/$DB.dump" --yes
check "data is back after full restore" \
  test "$(psql_admin -d "$DB" -c 'SELECT v FROM t')" = precious

finish
