#!/usr/bin/env bash
# Authoritative failure report for one `flutter test` run (phase 400 D2).
#
#   report_failures.sh <events.json> [list.txt]
#
# Reads the JSON event stream written by `flutter test --file-reporter
# json:<file>` and prints every failing test (suite path, test name, error,
# first stack lines). The console reporter of a multi-path `flutter test` can
# swallow output when piped (non-TTY); this stream cannot, so the failure list
# is complete regardless of what the console showed.
#
# Exit 1 when: the file is missing/empty/unparseable, the stream has no `done`
# event (truncated run), any testDone has result != success (hidden "loading
# <file>" pseudo-tests included: a compile/load error is a failure), or `done`
# reports success=false, or 0 real tests passed (a non-skipped, non-hidden
# testDone with result=success; an all-skipped / platform-filtered list is RED
# per stream, never masked by another stream's passes). With [list.txt] (the
# list run_list.sh ran), also exit 1 when a listed file has no `suite` event
# (e.g. `@TestOn('browser')` filtered it out, so it never ran). Exit 0 otherwise.
set -euo pipefail
file="${1:-}"; list="${2:-}"
[ -n "$file" ] && [ -s "$file" ] || { echo "report_failures: event stream '${file}' missing or empty"; exit 1; }

report="$(jq -R -s -r '
  split("\n") | map(fromjson? // empty) as $ev
  | ($ev | map(select(.type == "suite")) | map({key: (.suite.id | tostring), value: .suite.path}) | from_entries) as $suites
  | ($ev | map(select(.type == "testStart")) | map({key: (.test.id | tostring), value: .test}) | from_entries) as $tests
  | ($ev | map(select(.type == "error")) | group_by(.testID) | map({key: (.[0].testID | tostring), value: .}) | from_entries) as $errs
  | ($ev | map(select(.type == "testDone" and .result != "success"))) as $bad
  | ($ev | map(select(.type == "done")) | last) as $done
  | ($ev | map(select(.type == "testDone" and .result == "success"
        and (.hidden // false) == false and (.skipped // false) == false)) | length) as $passed
  | [ "parsed=\($ev | length)",
      "passed=\($passed)",
      "failed=\($bad | length)",
      "done=\(if $done == null then "missing" else ($done.success | tostring) end)" ]
    + ( $suites | to_entries | map("suite=\(.value // "")") )
    + ( $bad | map(
          ($tests[.testID | tostring] // {}) as $t
          | "FAILED: \($suites[($t.suiteID // -1) | tostring] // "?"): \($t.name // "test #\(.testID)") [\(.result)]"
          , ( ($errs[.testID | tostring] // []) | map(
                "  " + ((.error // "") | split("\n") | map(select(length > 0)) | .[:20] | join("\n  "))
                , "  " + ((.stackTrace // "") | split("\n") | map(select(length > 0)) | .[:8] | join("\n  ")) )
              | .[] ) ) )
    | .[]' <"$file")" || { echo "report_failures: unparseable event stream '$file'"; exit 1; }

field() { sed -n "s/^$1=//p" <<<"$report" | head -n1; }
parsed="$(field parsed)"; passed="$(field passed)"; failed="$(field failed)"; done_state="$(field 'done')"
if [ "${parsed:-0}" = "0" ]; then echo "report_failures: no JSON events in '$file'"; exit 1; fi
grep -v -E '^(parsed|passed|failed|done|suite)=' <<<"$report" || true
if [ "$done_state" = "missing" ]; then
  echo "report_failures RED: no 'done' event in '$file' (run truncated or killed)"; exit 1
fi
if [ "$failed" != "0" ]; then
  echo "report_failures RED: $failed failing test(s), $passed passed ($file)"; exit 1
fi
if [ "$done_state" != "true" ]; then
  echo "report_failures RED: run reported success=$done_state with no failing test event ($file)"; exit 1
fi
if [ "${passed:-0}" = "0" ]; then
  echo "report_failures RED: 0 non-skipped tests passed ($file): every selected test was skipped or filtered out"; exit 1
fi
if [ -n "$list" ]; then
  [ -f "$list" ] || { echo "report_failures: list '$list' not found"; exit 1; }
  suites="$(sed -n 's/^suite=//p' <<<"$report")"
  missing=0
  while IFS= read -r want || [ -n "$want" ]; do
    [ -n "$want" ] || continue
    # Suite paths are absolute or cwd-relative depending on the runner.
    found=0
    while IFS= read -r got; do
      if [ "$got" = "$want" ] || [[ "$got" == *"/$want" ]]; then found=1; break; fi
    done <<<"$suites"
    if [ "$found" -eq 0 ]; then
      echo "report_failures: listed file never loaded as a suite: $want"; missing=$((missing + 1))
    fi
  done <"$list"
  if [ "$missing" -ne 0 ]; then
    echo "report_failures RED: $missing listed file(s) produced no suite event ($file)"; exit 1
  fi
fi
echo "report_failures green: $passed passed, 0 failed ($file)"
