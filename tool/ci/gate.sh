#!/usr/bin/env bash
# ci-gate verdict (phase 397), FAIL CLOSED. Inputs (env):
#   NEEDS_JSON            toJSON(needs)
#   PLAN_MODE             needs.plan.outputs.mode
#   PLAN_SELECTION_COUNT  needs.plan.outputs.selection_count
#   EXPECT_TESTS          "true" when the tests must have run (mode full |
#                         selective on a non-noop event); then `tests-ran` (the
#                         base-owned "real tests executed" check) must be
#                         `success` (skipped / missing is RED), so must the two
#                         static-check jobs `gates-fast` and `gates` (they run
#                         on every non-noop event; audit F1 split the old
#                         `gates`) and `selector-tests` (a 3-leg matrix whose
#                         single result is success only if EVERY leg passed;
#                         audit cycle 2 N-L4: skipped / missing is RED, not
#                         merely "not failed"), and in mode FULL so must each of unit,
#                         tz-sweeps, goldens and apk (phase 402: the old single
#                         `test` job is split; a skipped one is RED, not a
#                         non-failure). `apk` is a debug/release matrix (audit
#                         F5): its single job result covers both legs.
#                         `coverage` is NON-BLOCKING (audit F2): codecov upload
#                         is informational (fail_ci_if_error: false), so a
#                         failed / cancelled / skipped coverage job is a
#                         ::warning::, never RED.
#                         In selective mode those jobs are legitimately skipped
#                         when their list is empty (a failure is still RED), and
#                         tests-ran owes a stream for every non-empty list.
#                         The compatibility `test` aggregator is NOT consulted.
# Red when:
#   - `plan` did not succeed (a failed plan skips everything downstream and a
#     skipped job reports success),
#   - any needed job failed / was cancelled (`skipped` is NOT a failure),
#   - PLAN_MODE is anything but full | selective | none (empty, garbage),
#   - PLAN_MODE=none while the selection is not provably empty (== "0").
# On PRs this script is executed from the BASE commit, never from the PR tree.
set -euo pipefail
: "${NEEDS_JSON:?NEEDS_JSON is required}"
PLAN_MODE="${PLAN_MODE:-}"
PLAN_SELECTION_COUNT="${PLAN_SELECTION_COUNT:-}"
EXPECT_TESTS="${EXPECT_TESTS:-}"
fail=0
bad="$(printf '%s' "$NEEDS_JSON" | jq -r '
  to_entries[]
  | select((.key == "plan" and .value.result != "success")
           or (.key != "coverage" and (.value.result == "failure" or .value.result == "cancelled")))
  | "\(.key)=\(.value.result)"')"
if [ -n "$bad" ]; then echo "ci-gate RED:"; echo "$bad" | sed 's/^/  /'; fail=1; fi
cov="$(printf '%s' "$NEEDS_JSON" | jq -r '.coverage.result // "missing"')"
if [ "$cov" = "failure" ] || [ "$cov" = "cancelled" ]; then
  echo "::warning::coverage job $cov (non-blocking: the codecov report is informational)"
fi
if [ "$EXPECT_TESTS" = "true" ]; then
  for j in gates-fast selector-tests gates; do
    jres="$(printf '%s' "$NEEDS_JSON" | jq -r --arg j "$j" '.[$j].result // "missing"')"
    if [ "$jres" != "success" ]; then echo "ci-gate RED: $j must be success (got $jres)"; fail=1; fi
  done
  if [ "$PLAN_MODE" = "full" ]; then
    if [ "$cov" = "skipped" ] || [ "$cov" = "missing" ]; then
      echo "::warning::coverage job was $cov in a full run (non-blocking)"
    fi
    for j in unit tz-sweeps goldens apk; do
      jres="$(printf '%s' "$NEEDS_JSON" | jq -r --arg j "$j" '.[$j].result // "missing"')"
      if [ "$jres" != "success" ]; then echo "ci-gate RED: $j must be success in a full run (got $jres)"; fail=1; fi
    done
  fi
  rres="$(printf '%s' "$NEEDS_JSON" | jq -r '.["tests-ran"].result // "missing"')"
  if [ "$rres" != "success" ]; then echo "ci-gate RED: tests-ran must be success (got $rres)"; fail=1; fi
fi
case "$PLAN_MODE" in
  full | selective) ;;
  none)
    if [ "$PLAN_SELECTION_COUNT" != "0" ]; then
      echo "ci-gate RED: mode=none but selection_count='$PLAN_SELECTION_COUNT' (must be 0)"; fail=1
    fi ;;
  *) echo "ci-gate RED: unknown plan mode '$(printf '%s' "$PLAN_MODE" | tr -c 'A-Za-z0-9_-' '?')'"; fail=1 ;;
esac
[ "$fail" -eq 0 ] || exit 1
echo "ci-gate green (mode=$PLAN_MODE): $(printf '%s' "$NEEDS_JSON" | jq -r 'to_entries | map("\(.key)=\(.value.result)") | join(", ")')"
