#!/usr/bin/env bash
# One attempt at an aggregating integration entry (phase 401, audit cycle 1:
# S5 / P3 / P5 / P7). Runs inside the emulator-runner `script:` and decides
# pass/fail for every group(...) the entry registers. Two callers:
#   * the selected-flow attempts (generated ci_selected_tests.dart), run from
#     the BASE checkout (trusted/);
#   * the full-suite shard attempts (generated ci_shard_tests.dart, 3 per
#     `integration-shard` matrix leg, 2026-11-06), run from the PR tree (full
#     mode has no trusted/ checkout; an edit here forces FULL mode, so in
#     selective mode the PR copy equals the base), label `SHARD K`.
#
#   run_it_attempt.sh <entry.dart> <log> <bound-seconds> <state-dir> [label]
#
# label: prefix of every verdict line (default `SELECTED FLOWS`); only
# letters, digits, spaces, `_` and `-` are kept.
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
# skip; result=failure, or any test with an `error` event (which also covers
# `failed after test completion`), is a failure -- hidden "loading <file>"
# pseudo-tests included, so a compile/load error is a failure.
# CANCELLED: a `testDone` with result=error and NO `error` event for its testID
# (except the hidden `loading <file>` pseudo-test: an errored load is always a
# real failure -- it precedes every test, so no device loss can cancel it).
# package:test emits exactly that for every remaining test when the device/
# emulator dies (device loss, docs/ci/emulator-integration.md#emulator-device-loss); the GitHub reporter
# still prints them with a check mark. Cancelled is NOT a real failure.
#
# Pass/fail (selected AND part attempts; the parts' old stdout `EXCEPTION
# banner + ✅` check passed runs whose tests were cancelled -- false green):
#   fail  the JSON file is missing / empty / unparseable / has no events
#         (`::error::`, loud);
#   fail  any real failing test (set -> <state-dir>/failset, see P5);
#   fail  no real failure but >= 1 cancelled test => `CRASHED ... retryable`
#         (emulator/device loss; clears state, never deterministic);
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
# Timeout (rc 124/137) => fail: slowness OR a hang. The line names the elapsed
# time and the last fully finished group. Two timeouts in a row (marker
# <state-dir>/timedout) => `deterministic=true`: a third attempt would only
# burn the bound again.
#
# SEC-5: the log is replayed with a leading `::` (also after leading
# whitespace) defused to `: :`, so a test printing `::add-mask::` /
# `::stop-commands::` cannot drive the runner.
#
# P5: after a REAL test failure (>= 1 failing test with a name) the sorted set of
# REAL failing test names (from the JSON testStart/testDone/error events;
# cancelled tests excluded) is stored in <state-dir>/failset. If the next attempt
# fails with the identical set, `deterministic=true` is appended to GITHUB_OUTPUT
# and the workflow skips the remaining attempt. Any other outcome (pass, crash /
# cancelled-only, hang, offline emulator, empty set) clears the state, so flakes
# keep all 3 attempts -- a crash point that repeats is still a crash, not a
# deterministic failure. Timeouts keep their own marker (above).
set -uo pipefail
entry="${1:?entry}"; log="${2:?log}"; bound="${3:?bound}"; state="${4:?state-dir}"
label="$(printf '%s' "${5:-SELECTED FLOWS}" | tr -cd 'A-Za-z0-9 _-')"
[ -n "$label" ] || label="SELECTED FLOWS"
flutter_bin="${FLUTTER:-flutter}"
[[ "$bound" =~ ^[0-9]+$ ]] && [ "$bound" -ge 1 ] || bound=1500
mkdir -p "$state"
failset_file="$state/failset"
timeout_file="$state/timedout"

clear_state() { rm -f "$failset_file" "$timeout_file"; }

replay() { sed -E 's/^([[:space:]]*)::/\1: :/' "$1"; }

# Last top-level group whose every declared test has a testDone (timeout line).
last_finished_group() {
  [ -s "$events" ] || { echo none; return; }
  jq -R -s -r '
    split("\n") | map(fromjson? // empty) | map(select(type == "object")) as $ev
    | ($ev | map(select(.type == "group") | .group)) as $gs
    | ($gs | map(select(.parentID == null) | .id)) as $roots
    | ($ev | map(select(.type == "testStart") | .test)) as $ts
    | ($ev | map(select(.type == "testDone") | .testID)) as $dn
    | [ $gs[] | select(.parentID as $p | $roots | any(. == $p)) | . as $g
        | ($ts | map(select(.groupIDs | any(. == $g.id)) | .id)) as $mine
        | select($g.testCount > 0 and ($mine | length) == $g.testCount
                 and ($mine | all(. as $i | $dn | any(. == $i))))
        | .name ] | last // "none"' <"$events" 2>/dev/null || echo none
}

# Fresh per attempt: a stale file from a previous attempt must never be judged.
events="$state/events.json"
rm -f "$events"

started=$SECONDS
timeout --signal=TERM --kill-after=60 "$bound" "$flutter_bin" test --reporter=github --file-reporter="json:$events" "$entry" >"$log" 2>&1
rc=$?
elapsed=$((SECONDS - started))
if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
  replay "$log"
  rm -f "$failset_file"
  echo "$label: TIMED OUT after ${elapsed}s (bound ${bound}s, rc=$rc); last fully finished group: $(last_finished_group). Slowness or a hang: compare the elapsed time and the groups still to run with the healthy shard time (docs/ci/emulator-integration.md#integration-shards). This bound is EXTERNAL on purpose: no in-isolate bound can catch event-loop starvation (Future.timeout, pumpAndSettle's deadline, pumpUntil* and defaultTestTimeout are all timers, see AppHarness.settle's doc). For a hang, look past the last finished group for an unbounded synchronous build (e.g. a per-hour/per-row loop driven by out-of-window data)."
  if [ -f "$timeout_file" ]; then
    echo "$label: the previous attempt timed out too (deterministic); the next attempt is skipped."
    [ -n "${GITHUB_OUTPUT:-}" ] && echo "deterministic=true" >>"$GITHUB_OUTPUT"
  fi
  : >"$timeout_file"
  exit 1
fi
replay "$log"

# Group names the entry registers: `group('<name>', <alias>.main)`, on one
# line or wrapped by dart format over several (the hand-written parts);
# `//` comments are stripped first, so a commented-out group never counts.
groups=()
while IFS= read -r g; do
  groups+=("$g")
done < <(sed 's://.*$::' "$entry" 2>/dev/null | tr '\n' ' ' |
  grep -oE "group\([[:space:]]*'[A-Za-z0-9_]+',[[:space:]]*[A-Za-z0-9_]+\.main,?[[:space:]]*\)" |
  sed -E "s/^group\([[:space:]]*'([A-Za-z0-9_]+)'.*/\1/")

if [ ! -s "$events" ]; then
  clear_state
  echo "::error::JSON event stream '$events' is missing or empty -- the host runner wrote no --file-reporter output (flutter crashed before running, the report format changed, or the run died); a teardown flake is retried."
  exit 1
fi

want_json="$(printf '%s\n' "${groups[@]+"${groups[@]}"}" | jq -R -s -c 'split("\n") | map(select(length > 0))')" || want_json='[]'

# Output lines (tab separated; test names have newlines/tabs flattened):
#   P <events>      parsed event count        D <true|false|missing>  final `done` (informational)
#   F <name>        one per REAL failing test G <group> ok|bad <detail>
#   C <n>           cancelled test count      L <name>  last passing test (or none)
report="$(jq -R -s -r --argjson want "$want_json" '
  def flat: gsub("[\n\r\t]"; " ");
  split("\n") | map(fromjson? // empty) | map(select(type == "object")) as $ev
  | ($ev | map(select(.type == "group") | .group)) as $gs
  | ($gs | map(select(.parentID == null) | .id)) as $roots
  | ($ev | map(select(.type == "testStart") | .test)) as $ts
  | ($ts | map({key: (.id | tostring), value: .}) | from_entries) as $byid
  | ($ev | map(select(.type == "testDone")) | map({key: (.testID | tostring), value: .}) | from_entries) as $done
  | ($ev | map(select(.type == "error") | .testID | tostring)) as $errids
  | ($done | to_entries | map(select(.value.result == "error") | .key)
      | map(select(($byid[.].name // "") | startswith("loading ")))) as $loaderr
  | ($done | to_entries | map(select(.value.result == "error") | .key)
      | map(. as $id | select((($errids + $loaderr) | index($id)) | not))) as $cancelled
  | ( ( ($done | to_entries | map(select(.value.result != "success" and .value.result != "error") | .key)) + $errids + $loaderr )
      | unique | map(. as $id | ($byid[$id].name // "test #\($id)") | flat) | unique ) as $failed
  | ($ev | map(select(.type == "testDone" and .result == "success" and (.skipped // false) == false and (.hidden // false) == false))
      | last) as $lastok
  | ($ev | map(select(.type == "done")) | last) as $dn
  | [ "P\t\($ev | length)",
      "D\t\(if $dn == null then "missing" else ($dn.success | tostring) end)",
      "C\t\($cancelled | length)",
      "L\t\(if $lastok == null then "none" else (($byid[$lastok.testID | tostring].name // "test #\($lastok.testID)") | flat) end)" ]
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
  echo "::error::JSON event stream '$events' is unparseable or holds no events -- cannot judge the $label run."
  exit 1
fi
cur="$(field F | sort -u)"
done_state="$(field D | head -n1)"
cancelled="$(field C | head -n1)"
last_ok="$(field L | head -n1)"

if [ -n "$cur" ]; then
  echo "$label: FAILED — a real test failure/error was reported by the JSON test protocol."
  printf '  failing: %s\n' "$(tr '\n' ';' <<<"$cur")"
  if [ -f "$failset_file" ] && [ "$(cat "$failset_file")" = "$cur" ]; then
    echo "$label: the failing-test set is identical to the previous attempt's (deterministic failure); the next attempt is skipped."
    [ -n "${GITHUB_OUTPUT:-}" ] && echo "deterministic=true" >>"$GITHUB_OUTPUT"
  fi
  printf '%s\n' "$cur" >"$failset_file"
  rm -f "$timeout_file"
  exit 1
fi
clear_state

if [ -n "$cancelled" ] && [ "$cancelled" != "0" ]; then
  echo "$label: CRASHED after ${last_ok:-none}; ${cancelled} tests cancelled (emulator/device loss) — retryable"
  exit 1
fi

if [ "${#groups[@]}" -eq 0 ]; then
  echo "$label: FAILED — no group(...) lines could be read from $entry."
  exit 1
fi

bad="$(sed -n 's/^G\t\([^\t]*\)\tbad\t/\1: /p' <<<"$report")"
if [ -n "$bad" ]; then
  echo "$label: FAILED — these groups did not fully pass in the JSON stream (a crash mid-group, a flow that never ran, or only skips; done=$done_state):"
  sed 's/^/  /' <<<"$bad"
  exit 1
fi
echo "$label: All ${#groups[@]} groups ran and every test passed (JSON protocol; done=$done_state)."
exit 0
