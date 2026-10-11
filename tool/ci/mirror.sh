#!/usr/bin/env bash
# Mirror-mode helpers for `ci-gate` on irrelevant-label (noop) events (phase 397).
# A noop `labeled` run skips every job; if ci-gate were skipped too, GitHub would
# treat the skipped required check as passing and it could mask a red/pending real
# ci-gate on the same head SHA. So ci-gate always runs and mirrors the real run.
#
#   mirror.sh select <pr-number>
#                       stdin = `gh api repos/{o}/{r}/actions/runs?head_sha=<sha>
#                       &event=pull_request` (object with .workflow_runs[]);
#                       env CURRENT_RUN_ID. Prints the id of the latest
#                       pr-validate pull_request run that belongs to THIS PR
#                       (pull_requests[].number), excluding noop runs and the
#                       current run. Prints nothing if none. (Fork PRs report an
#                       empty pull_requests list -> nothing selected -> the caller
#                       fails closed.)
#   mirror.sh verdict <status> <conclusion>
#                       exit 0 only for completed + success; everything else
#                       (empty, in_progress, cancelled, failure, ...) exits 1.
# On PRs this script is executed from the BASE commit, never from the PR tree.
set -euo pipefail
case "${1:-}" in
  select)
    : "${CURRENT_RUN_ID:?CURRENT_RUN_ID is required}"
    pr="${2:-}"
    case "$pr" in '' | *[!0-9]*) echo "mirror: select needs a numeric PR number" >&2; exit 2 ;; esac
    jq -r --arg cur "$CURRENT_RUN_ID" --argjson pr "$pr" '
      (.workflow_runs // [])
      | map(select(.event == "pull_request"
                   and .path == ".github/workflows/pr-validate.yml"
                   and (.id | tostring) != $cur
                   and ((.display_title // "") | startswith("label-noop") | not)
                   and ((.pull_requests // []) | any(.number == $pr))))
      | sort_by(.id) | last | .id // empty'
    ;;
  verdict)
    if [ "${2:-}" = "completed" ] && [ "${3:-}" = "success" ]; then
      echo "mirror: real run concluded success"
    else
      echo "mirror RED: real run status='${2:-}' conclusion='${3:-}'"; exit 1
    fi
    ;;
  *) echo "usage: mirror.sh select <pr>|verdict <status> <conclusion>" >&2; exit 2 ;;
esac
