#!/usr/bin/env bash
# "Tests actually ran" check for the `test` job. A PR that edits test config or
# the harness could make every test skip (or vanish) and still exit 0; this
# counts the tests that PASSED and were NOT skipped from `flutter test`'s JSON
# event stream (`--file-reporter json:<file>`).
#
#   tests_ran.sh <events.json> full <floor-file>   passed >= floor and > 0
#   tests_ran.sh <events.json> selective           passed > 0
#
# Counted: `testDone` events with result=success, skipped=false, hidden=false
# (hidden = synthetic "loading <file>" pseudo-tests). A failed/errored run is
# the test step's own problem; this only proves "something real executed".
# Executed from the BASE commit on PRs, floor file included (ratchet owned by
# base: raise tool/ci/min_tests.txt in a reviewed PR, never lower it silently).
# Floor derivation (min_tests.txt must stay a bare integer, no comments): ~85% of the
# +N passed counter of the CI unit step (`flutter test --coverage --exclude-tags golden`,
# the only stream feeding unit-events.json) = 11066 (dev run 37980306121, 2026-10-09)
# -> 9400. NOT the declaration count (~9.7k): declarations != executed tests.
set -euo pipefail
file="${1:-}"; mode="${2:-}"
[ -n "$file" ] && [ -f "$file" ] || { echo "tests-ran RED: events file '${file}' missing"; exit 1; }
passed="$(jq -R -s -r '
  split("\n") | map(fromjson? // empty)
  | map(select(.type == "testDone" and .result == "success"
               and (.skipped // false) == false and (.hidden // false) == false))
  | length' <"$file")"
case "$passed" in '' | *[!0-9]*) echo "tests-ran RED: unparseable event stream"; exit 1 ;; esac
case "$mode" in
  full)
    floor_file="${3:-}"
    [ -n "$floor_file" ] && [ -f "$floor_file" ] || { echo "tests-ran RED: floor file '${floor_file}' missing"; exit 1; }
    floor="$(tr -d '[:space:]' <"$floor_file")"
    case "$floor" in '' | *[!0-9]*) echo "tests-ran RED: floor '$floor' not a number"; exit 1 ;; esac
    if [ "$passed" -eq 0 ] || [ "$passed" -lt "$floor" ]; then
      echo "tests-ran RED: $passed non-skipped tests passed, floor is $floor"; exit 1
    fi
    echo "tests-ran green: $passed non-skipped tests passed (floor $floor)" ;;
  selective)
    if [ "$passed" -eq 0 ]; then echo "tests-ran RED: 0 non-skipped tests passed for a non-empty selection"; exit 1; fi
    echo "tests-ran green: $passed non-skipped tests passed (selective)" ;;
  *) echo "usage: tests_ran.sh <events.json> full <floor-file> | selective" >&2; exit 2 ;;
esac
