#!/usr/bin/env bash
# Forbid `schedule` coupling in .github/workflows/pr-validate.yml (phase 396).
#
# WHY THIS EXISTS
# ---------------
# A `schedule` event always runs the workflow file from the DEFAULT branch
# (main). The nightly patrol job used to check out `dev` on schedule, pairing
# main's workflow with dev's code. dev's avatar_pick_patrol_test needed a
# gallery-seed step that main's workflow lacked -> empty Photo Picker -> exit
# 124 on four consecutive nights (runs 37607733041 ... 38043590964).
#
# The nightly now lives in .github/workflows/nightly.yml, which dispatches
# pr-validate.yml ON dev (workflow + code from the same branch). This gate
# keeps the skew from coming back. Fails (exit 1) when pr-validate.yml has, on a
# non-comment line:
#   1. a `schedule:` key,
#   2. a `ref:` expression that mentions `schedule`,
#   3. a `github.event_name == 'schedule'` condition (dead without the trigger).
#
# Usage: forbid_schedule_in_pr_validate.sh [file]   (default: the real workflow)
#        forbid_schedule_in_pr_validate.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"

# scan <file>: print offending lines "line:rule:text"; return 1 if any.
scan() {
  local out
  out="$(awk '
    /^[ \t]*#/ { next }
    /^[ \t]*schedule[ \t]*:/            { printf "%d:schedule: key:%s\n", NR, $0; next }
    /^[ \t]*ref[ \t]*:.*schedule/       { printf "%d:ref: mentions schedule:%s\n", NR, $0; next }
    /event_name[ \t]*==[ \t]*.schedule./ { printf "%d:event_name == schedule:%s\n", NR, $0; next }
  ' "$1")"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 1
  fi
  return 0
}

self_test() {
  local tmp rc=0 status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  printf 'on:\n  workflow_dispatch: {}\n  # schedule: documented in a comment\njobs:\n  a:\n    steps:\n      - uses: x\n' >"$tmp/ok.yml"
  printf 'on:\n  schedule:\n    - cron: "0 0 * * *"\n' >"$tmp/key.yml"
  printf 'steps:\n  - uses: x\n    with:\n      ref: ${{ github.event_name == '"'"'schedule'"'"' && '"'"'dev'"'"' || '"'"''"'"' }}\n' >"$tmp/ref.yml"
  printf 'jobs:\n  a:\n    if: github.event_name == '"'"'schedule'"'"'\n' >"$tmp/cond.yml"
  printf 'paths:\n  - test/features/schedule/\n' >"$tmp/path.yml"

  run_case() { # name expect file
    set +e; scan "$3" >/dev/null 2>&1; status=$?; set -e
    if [ "$status" -eq "$2" ]; then printf '  PASS  %s\n' "$1"
    else printf '  FAIL  %s (expected rc=%s, got rc=%s)\n' "$1" "$2" "$status"; rc=1; fi
  }
  echo "forbid_schedule_in_pr_validate --self-test"
  run_case "clean workflow (schedule only in a comment)" 0 "$tmp/ok.yml"
  run_case "schedule: key"                               1 "$tmp/key.yml"
  run_case "ref: expression mentions schedule"           1 "$tmp/ref.yml"
  run_case "event_name == 'schedule' condition"          1 "$tmp/cond.yml"
  run_case "unrelated test/features/schedule/ path"      0 "$tmp/path.yml"
  return $rc
}

if [ "${1:-}" = "--self-test" ]; then
  if self_test; then echo "SELF-TEST OK: forbid_schedule_in_pr_validate.sh"; exit 0; fi
  exit 1
fi

target="${1:-$repo_root/.github/workflows/pr-validate.yml}"
if [ ! -f "$target" ]; then
  echo "forbid_schedule_in_pr_validate: $target not found" >&2
  exit 1
fi

set +e; offenders="$(scan "$target")"; status=$?; set -e
if [ "$status" -ne 0 ]; then
  echo "ERROR: pr-validate.yml regained a schedule coupling (phase 396)."
  echo
  printf '%s\n' "$offenders" | sed 's/^/  line /'
  echo
  echo "A schedule run uses main's workflow but a dev checkout -> workflow/code skew."
  echo "Put the schedule in .github/workflows/nightly.yml (dispatches pr-validate on dev)."
  exit 1
fi
echo "forbid_schedule_in_pr_validate: OK — no schedule coupling in pr-validate.yml."
