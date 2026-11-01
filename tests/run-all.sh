#!/usr/bin/env bash
# Run every test and print a summary.
# Usage: ./run-all.sh            (all tests)
#        ./run-all.sh --no-restart (skip 03, which restarts the database pod)
cd "$(dirname "$0")"

FAILED=()
for TEST in [0-9][0-9]-*.sh; do
  if [[ "${1:-}" == "--no-restart" && "$TEST" == 03-* ]]; then
    echo "== skipping $TEST"; continue
  fi
  bash "$TEST" || FAILED+=("$TEST")
  echo
done

if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
