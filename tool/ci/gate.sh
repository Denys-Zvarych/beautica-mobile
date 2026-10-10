#!/usr/bin/env bash
# ci-gate verdict (phase 397), FAIL CLOSED. Inputs (env):
#   NEEDS_JSON            toJSON(needs)
#   PLAN_MODE             needs.plan.outputs.mode
#   PLAN_SELECTION_COUNT  needs.plan.outputs.selection_count
#   EXPECT_TESTS          "true" when the `test` job must have run (mode full |
#                         selective on a non-noop event); then `test` must be
#                         `success` (a skipped `test` is RED, not a non-failure),
#                         and so must `tests-ran` (the base-owned "real tests
#                         executed" check; skipped / missing is RED too)
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
           or .value.result == "failure" or .value.result == "cancelled")
  | "\(.key)=\(.value.result)"')"
if [ -n "$bad" ]; then echo "ci-gate RED:"; echo "$bad" | sed 's/^/  /'; fail=1; fi
if [ "$EXPECT_TESTS" = "true" ]; then
  tres="$(printf '%s' "$NEEDS_JSON" | jq -r '.test.result // "missing"')"
  if [ "$tres" != "success" ]; then echo "ci-gate RED: test must be success (got $tres)"; fail=1; fi
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
