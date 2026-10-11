#!/usr/bin/env bash
# One attempt at the generated selective integration entry (phase 401, audit
# cycle 1: S5 / P3 / P5 / P7). Runs from the BASE checkout (trusted/) inside
# the emulator-runner `script:`; it decides pass/fail for the selected flows.
#
#   run_it_attempt.sh <entry.dart> <log> <bound-seconds> <state-dir>
#
# env: FLUTTER (flutter binary, default `flutter`), GITHUB_OUTPUT (optional).
#
# Verdict source (audit cycle 4, SEC LOW): the MACHINE-READABLE JSON test protocol
# that the HOST-side flutter_tools runner writes via `--file-reporter json:<file>`
# (<state-dir>/events.json) -- NOT the human-readable stdout. A test's print()
# reaches that file only as `{"type":"print",...}` events (never as `testDone` /
# `group` events), so it cannot fabricate a pass; the on-device test code also
# cannot write the host file. `--reporter=github` is kept for the humans reading
# the log (which is only replayed, never judged). Feasibility (Flutter 3.41.9):
# flutter_tools test/runner.dart passes `--file-reporter=<..>` into the package:test
# argv for host AND integration-device runs (the device is only a platform
# plugin feeding the same Engine/reporters), see commands/test.dart `file-reporter`.
#
# Event semantics reused from phase 400 (report_failures.sh / tests_ran.sh): a
# real test is a `testDone` with hidden=false; result=success + skipped=true is a
# skip; any other result (and any `error` event, which also covers
# `failed after test completion`) is a failure -- hidden "loading <file>"
# pseudo-tests included, so a compile/load error is a failure.
#
# Pass/fail (selected attempts only; the six full-mode part steps keep their
# byte-identical inline `EXCEPTION banner + ✅` check, phase acceptance):
#   fail  the JSON file is missing / empty / unparseable / has no events
#         (`::error::`, loud);
#   fail  any failing test (set -> <state-dir>/failset, see P5);
#   pass  EVERY `group('<name>', ...)` of the entry exists exactly once as a
#         top-level group (parentID = the suite's root group) in the stream, has
#         >= 1 non-skipped passing test, and
#         (passing + skipped) == the group's declared `testCount` == the number
#         of tests started under it (groupIDs). A flow that never ran, or a
#         crash mid-group (fewer testDone than testCount), cannot pass;
#   fail  anything else.
# The final `done` event's `success` is deliberately IGNORED and its absence is
# tolerated: the known emulator-teardown flake (`adb: device offline`) kills the
# run AFTER the last test finished, so the stream may end without `done` or with
# success=false even though every test passed. The per-group count above is what
# proves completion (a mid-run crash leaves a group short of its testCount), and
# real failures are caught by the testDone/error scan, so `done` adds nothing.
# rc is NOT used either (the same flake exits non-zero after a real pass).
# Timeout (rc 124/137) is a HANG => fail.
#
# SEC-5: the log is replayed with a leading `::` defused, so a test printing
# `::add-mask::` / `::stop-commands::` cannot drive the runner.
#
# P5: after a REAL test failure (>= 1 failing test with a name) the sorted set of
# failing test names (from the JSON testStart/testDone/error events) is stored in
# <state-dir>/failset. If the next attempt fails with the identical set,
# `deterministic=true` is appended to GITHUB_OUTPUT and the workflow skips the
# remaining attempt. Any other outcome (pass, crash, hang, offline emulator,
# empty set) clears the state, so flakes keep all 3 attempts.
set -uo pipefail
entry="${1:?entry}"; log="${2:?log}"; bound="${3:?bound}"; state="${4:?state-dir}"
flutter_bin="${FLUTTER:-flutter}"
[[ "$bound" =~ ^[0-9]+$ ]] && [ "$bound" -ge 1 ] || bound=1500
mkdir -p "$state"
failset_file="$state/failset"

clear_state() { rm -f "$failset_file"; }

replay() { sed 's/^::/ ::/' "$1"; }

# Fresh per attempt: a stale file from a previous attempt must never be judged.
events="$state/events.json"
rm -f "$events"

timeout --signal=TERM --kill-after=60 "$bound" "$flutter_bin" test --reporter=github --file-reporter="json:$events" "$entry" >"$log" 2>&1
rc=$?
if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
  replay "$log"
  clear_state
  echo "SELECTED FLOWS: TIMED OUT after ${bound}s (rc=$rc). This bound is EXTERNAL on purpose: no in-isolate bound can catch event-loop starvation. Future.timeout, pumpAndSettle's own deadline, pumpUntil* poll deadlines and defaultTestTimeout are ALL timers, and a timer never fires while a synchronous allocating loop holds the isolate (see AppHarness.settle's doc). A healthy run is far under this bound, so treat 124/137 as a HANG, not slowness: find the last flow that logged and look for an unbounded synchronous build (e.g. a per-hour/per-row loop driven by out-of-window data)."
  exit 1
fi
replay "$log"

# Group names the entry registers (`  group('<name>', <alias>.main);`).
groups=()
while IFS= read -r g; do
  groups+=("$g")
done < <(sed -n "s/^  group('\([A-Za-z0-9_]*\)', .*/\1/p" "$entry" 2>/dev/null)

if [ ! -s "$events" ]; then
  clear_state
  echo "::error::JSON event stream '$events' is missing or empty -- the host runner wrote no --file-reporter output (flutter crashed before running, the report format changed, or the run died); a teardown flake is retried."
  exit 1
fi

want_json="$(printf '%s\n' "${groups[@]+"${groups[@]}"}" | jq -R -s -c 'split("\n") | map(select(length > 0))')" || want_json='[]'

# Output lines (tab separated; test names have newlines/tabs flattened):
#   P <events>      parsed event count        D <true|false|missing>  final `done` (informational)
#   F <name>        one per failing test      G <group> ok|bad <detail>
report="$(jq -R -s -r --argjson want "$want_json" '
  def flat: gsub("[\n\r\t]"; " ");
  split("\n") | map(fromjson? // empty) | map(select(type == "object")) as $ev
  | ($ev | map(select(.type == "group") | .group)) as $gs
  | ($gs | map(select(.parentID == null) | .id)) as $roots
  | ($ev | map(select(.type == "testStart") | .test)) as $ts
  | ($ts | map({key: (.id | tostring), value: .}) | from_entries) as $byid
  | ($ev | map(select(.type == "testDone")) | map({key: (.testID | tostring), value: .}) | from_entries) as $done
  | ($ev | map(select(.type == "error") | .testID | tostring)) as $errids
  | ( ( ($done | to_entries | map(select(.value.result != "success") | .key)) + $errids )
      | unique | map(. as $id | ($byid[$id].name // "test #\($id)") | flat) | unique ) as $failed
  | ($ev | map(select(.type == "done")) | last) as $dn
  | [ "P\t\($ev | length)",
      "D\t\(if $dn == null then "missing" else ($dn.success | tostring) end)" ]
    + ( $failed | map("F\t\(.)") )
    + ( $want | map(. as $g
        | ($gs | map(select(.name == $g and (.parentID as $p | $roots | any(. == $p))))) as $m
        | if ($m | length) != 1 then "G\t\($g)\tbad\t\($m | length) top-level group event(s) named it"
          else $m[0] as $grp
            | ($ts | map(select(.groupIDs | any(. == $grp.id)))) as $mine
            | ($mine | map($done[(.id | tostring)]) | map(select(. != null and .result == "success"))) as $okd
            | ($okd | map(select((.skipped // false) == false and (.hidden // false) == false)) | length) as $pass
            | ($okd | map(select((.skipped // false) == true)) | length) as $skip
            | if $pass >= 1 and ($pass + $skip) == $grp.testCount and ($mine | length) == $grp.testCount
              then "G\t\($g)\tok\t\($pass) passed, \($skip) skipped"
              else "G\t\($g)\tbad\t\($pass) passed + \($skip) skipped of \($grp.testCount) declared (\($mine | length) started)" end
          end ) )
  | .[]' <"$events")" || report=""

field() { sed -n "s/^$1\t//p" <<<"$report"; }
parsed="$(field P | head -n1)"
if [ -z "$report" ] || [ -z "$parsed" ] || [ "$parsed" = "0" ]; then
  clear_state
  echo "::error::JSON event stream '$events' is unparseable or holds no events -- cannot judge the selected flows."
  exit 1
fi
cur="$(field F | sort -u)"
done_state="$(field D | head -n1)"

if [ -n "$cur" ]; then
  echo "SELECTED FLOWS: FAILED — a real test failure/error was reported by the JSON test protocol."
  printf '  failing: %s\n' "$(tr '\n' ';' <<<"$cur")"
  if [ -f "$failset_file" ] && [ "$(cat "$failset_file")" = "$cur" ]; then
    echo "SELECTED FLOWS: the failing-test set is identical to the previous attempt's (deterministic failure); the next attempt is skipped."
    [ -n "${GITHUB_OUTPUT:-}" ] && echo "deterministic=true" >>"$GITHUB_OUTPUT"
  fi
  printf '%s\n' "$cur" >"$failset_file"
  exit 1
fi
clear_state

if [ "${#groups[@]}" -eq 0 ]; then
  echo "SELECTED FLOWS: FAILED — no group(...) lines could be read from $entry."
  exit 1
fi

bad="$(sed -n 's/^G\t\([^\t]*\)\tbad\t/\1: /p' <<<"$report")"
if [ -n "$bad" ]; then
  echo "SELECTED FLOWS: FAILED — these selected groups did not fully pass in the JSON stream (a crash mid-group, a flow that never ran, or only skips; done=$done_state):"
  sed 's/^/  /' <<<"$bad"
  exit 1
fi
echo "SELECTED FLOWS: All ${#groups[@]} selected groups ran and every test passed (JSON protocol; done=$done_state)."
exit 0
