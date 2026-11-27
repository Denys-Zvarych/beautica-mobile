#!/usr/bin/env bash
# CI plan (phase 397): decides the run MODE and the native-surface flag, and owns
# the one diff every later job consumes.
#
# Inputs (env):
#   EVENT_NAME   github.event_name (push | pull_request | workflow_dispatch | ...)
#   LABELS       comma-joined PR label names (pull_request only)
#   BASE_SHA     github.event.pull_request.base.sha   (pull_request only)
#   HEAD_SHA     the checked-out commit (pull_request and push)
#   EVENT_BEFORE github.event.before (push only; phase 566 L1 push diff base)
#   PR_DRAFT     github.event.pull_request.draft (phase 566 L3 it_fanout)
#   PR_BASE_REF / PR_HEAD_REF  pull_request base.ref / head.ref (566 L11:
#                main <- dev = promotion PR, always full; any repo, stricter is safe)
#   SELECTIVE_ENABLED  'true' once phase 400 wires selection; until then a
#                selective PR still runs EVERYTHING (run_all=true). Default false.
#   PLAN_CHANGES_FILE  test hook: use this name-status list instead of git.
#   PLAN_FORCE_MERGE_BASE_FAIL=1  test hook: simulate a failed merge-base.
#   PLAN_OUT_DIR  REQUIRED. Where changes.txt is written. Must be OUTSIDE the
#                checked-out PR tree (the workflow passes $RUNNER_TEMP/ci): a PR
#                controls everything under its tree, incl. symlinks. Refused (exit 1)
#                if unset, a symlink, not owned by the runner user, or inside $PWD.
#   GITHUB_OUTPUT / GITHUB_STEP_SUMMARY  used when set, else stdout.
#
# Outputs: mode (full|selective), native (true|false), run_all (true|false),
#          base, head, changed_count, changes_dir, it_fanout, selector_needed.
#          Changed list: $PLAN_OUT_DIR/changes.txt
#          ("STATUS<TAB>path[<TAB>newpath]", `git diff -z --name-status -M`, unquoted).
#
# Mode: full for workflow_dispatch (manual + nightly), PRs labelled `full-ci`,
# anything unrecognised, or a failed merge-base. Otherwise selective: a PR on
# its merge-base diff, a push (phase 566 L1) on EVENT_BEFORE..HEAD_SHA; an
# empty / all-zero / unreachable `before` is the same fail-safe full.
# native mirrors the retired dorny/paths-filter `changes` job globs exactly; it
# is only meaningful for PRs (other events never gate patrol on a diff).
# it_fanout (L3): false on push and on a draft PR without `full-ci`; never
# changes mode. selector_needed (L7): gates ONLY the two e2e selector-test legs
# (the fast leg always runs); false ONLY on a selective PR whose diff touches no
# e2e-leg input (is_e2e_leg_input: .github/** + tool/ci/**, pinned by TC-9 in
# workflow_wiring_test.dart); true otherwise (full, push, dispatch, fail-safe).
# Promotion PR (L11): mode=full, it_fanout=true, selector_needed=true, always.

set -euo pipefail

EVENT_NAME="${EVENT_NAME:-}"
LABELS="${LABELS:-}"
BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-}"
EVENT_BEFORE="${EVENT_BEFORE:-}"
PR_DRAFT="${PR_DRAFT:-false}"
PR_BASE_REF="${PR_BASE_REF:-}"
PR_HEAD_REF="${PR_HEAD_REF:-}"
SELECTIVE_ENABLED="${SELECTIVE_ENABLED:-false}"
OUT_DIR="${PLAN_OUT_DIR:-}"

die() { echo "plan.sh: $*" >&2; exit 1; }

# Output location hardening (fail closed -> plan job red -> ci-gate red).
[ -n "$OUT_DIR" ] || die "PLAN_OUT_DIR is required (must be outside the PR tree)"
[ ! -L "$OUT_DIR" ] || die "PLAN_OUT_DIR is a symlink: $OUT_DIR"
mkdir -p "$OUT_DIR"
[ -d "$OUT_DIR" ] && [ ! -L "$OUT_DIR" ] || die "PLAN_OUT_DIR is not a plain directory: $OUT_DIR"
[ -O "$OUT_DIR" ] || die "PLAN_OUT_DIR is not owned by the current user: $OUT_DIR"
out_real="$(cd -P "$OUT_DIR" && pwd -P)"
cwd_real="$(pwd -P)"
case "$out_real/" in
  "$cwd_real"/*) die "PLAN_OUT_DIR resolves inside the working tree: $out_real" ;;
esac
OUT_DIR="$out_real"
changes_file="$OUT_DIR/changes.txt"
# rm -f on a symlink removes the link, never its target; noclobber (O_EXCL)
# then refuses to follow anything planted between the rm and the create.
rm -f "$changes_file"
( set -o noclobber; : >"$changes_file" ) || die "cannot create $changes_file exclusively"
[ -f "$changes_file" ] && [ ! -L "$changes_file" ] && [ -O "$changes_file" ] || die "unsafe changes file: $changes_file"

mode="full"
reason=""
fail_safe=0
promotion=0
e2e_input=0
native="false"
changed_count="n/a"
base="$BASE_SHA"
head="$HEAD_SHA"

# diff_to_file <mb> <head> <out>: NUL-delimited, unquoted-path `git diff
# --name-status -M`, rewritten to "STATUS<TAB>path[<TAB>newpath]" lines. Non-ASCII
# paths survive verbatim (no octal quoting). A path containing TAB or newline
# cannot be represented in that format -> return 1 (caller fails safe to full).
diff_to_file() {
  local raw st a b
  raw="$(mktemp)"
  git -c core.quotepath=false diff -z --name-status -M "$1" "$2" >"$raw" 2>/dev/null || { rm -f "$raw"; return 1; }
  : >"$3"
  while IFS= read -r -d '' st; do
    IFS= read -r -d '' a || { rm -f "$raw"; return 1; }
    b=""
    case "$st" in R* | C*) IFS= read -r -d '' b || { rm -f "$raw"; return 1; } ;; esac
    case "$a$b" in *$'\t'* | *$'\n'*) rm -f "$raw"; return 1 ;; esac
    if [ -n "$b" ]; then printf '%s\t%s\t%s\n' "$st" "$a" "$b" >>"$3"; else printf '%s\t%s\n' "$st" "$a" >>"$3"; fi
  done <"$raw"
  rm -f "$raw"
}

# pubspec_version_only <base> <head> (sibling script): a pubspec.yaml change that
# touches ONLY the top-level `version:` line (release bump) is not native. Missing
# helper or any git failure -> pubspec.yaml stays native (fail closed).
# shellcheck source=tool/ci/pubspec_version_only.sh
if ! . "$(dirname "${BASH_SOURCE[0]}")/pubspec_version_only.sh" 2>/dev/null ||
   ! declare -F pubspec_version_only >/dev/null; then
  pubspec_version_only() { return 1; }
fi

# is_e2e_leg_input <path> (566 L7/Q2): every repo path the e2e selector-test legs
# (e2e-a, e2e-b) read or import: CI machinery only (their Dart deps are pinned by
# tool/ci/affected_tests/pubspec.lock, the SDK by .github). TC-9 parses this list
# and fails if an e2e-leg read appears outside it.
is_e2e_leg_input() {
  case "$1" in
    .github/* | tool/ci/*) return 0 ;;
  esac
  return 1
}

# is_native_path <path>: identical globs to the retired `changes` job.
is_native_path() {
  case "$1" in
    android/* | */AndroidManifest.xml | AndroidManifest.xml) return 0 ;;
    integration_test/patrol/*) return 0 ;;
    lib/routing/*) return 0 ;;
    lib/main.dart | pubspec.yaml) return 0 ;;
    .github/workflows/pr-validate.yml) return 0 ;;
  esac
  return 1
}

case "$EVENT_NAME" in
  push)
    mode="selective"
    reason="push (selective on the push diff)"
    base="$EVENT_BEFORE"
    ;;
  workflow_dispatch) reason="workflow_dispatch (manual or nightly)" ;;
  pull_request)
    if [ "$PR_BASE_REF" = main ] && [ "$PR_HEAD_REF" = dev ]; then
      promotion=1
      reason="promotion PR dev->main (566 L11: always full)"
    elif [[ ",$LABELS," == *",full-ci,"* ]]; then
      reason="PR labelled full-ci"
    else
      mode="selective"
      reason="pull request"
    fi
    ;;
  *) reason="unrecognised event '$EVENT_NAME' (fail-safe)" ;;
esac

# The push diff base must be a real commit id: empty or all-zero (new branch,
# force-push) => no diff => fail-safe full below.
push_before_ok() { [[ "$EVENT_BEFORE" =~ ^[0-9a-f]{7,64}$ ]] && [[ ! "$EVENT_BEFORE" =~ ^0+$ ]]; }

if [ "$EVENT_NAME" = "pull_request" ] || [ "$EVENT_NAME" = "push" ]; then
  mb=""
  if [ "$EVENT_NAME" = "push" ]; then BASE_SHA="$EVENT_BEFORE"; fi
  if [ "$EVENT_NAME" = "push" ] && ! push_before_ok; then
    :
  elif [ -n "${PLAN_CHANGES_FILE:-}" ]; then
    if [ "${PLAN_FORCE_MERGE_BASE_FAIL:-0}" != "1" ]; then
      cp "$PLAN_CHANGES_FILE" "$changes_file"
      mb="fixture"
    fi
  elif [ -n "$BASE_SHA" ] && [ -n "$HEAD_SHA" ] && [ "${PLAN_FORCE_MERGE_BASE_FAIL:-0}" != "1" ]; then
    if mb="$(git merge-base "$BASE_SHA" "$HEAD_SHA" 2>/dev/null)" &&
       diff_to_file "$mb" "$HEAD_SHA" "$changes_file"; then
      :
    else
      mb=""
    fi
  fi

  if [ -z "$mb" ]; then
    mode="full"
    # unknown PR diff -> do not risk skipping the native tier (push: as before)
    if [ "$EVENT_NAME" = "pull_request" ]; then native="true"; fi
    reason="merge-base/diff failed (fail-safe full)"
    fail_safe=1
    : >"$changes_file"
  else
    changed_count="$(grep -c . "$changes_file" || true)"
    while IFS=$'\t' read -r _status p1 p2; do
      for p in "$p1" "${p2:-}"; do
        [ -n "$p" ] || continue
        if is_e2e_leg_input "$p"; then e2e_input=1; fi
        if is_native_path "$p"; then
          # Version-only bump of pubspec.yaml (real merge-base diff) is not native.
          if [ "$p" = pubspec.yaml ] && pubspec_version_only "$mb" "$HEAD_SHA"; then
            :
          else
            native="true"
          fi
        fi
      done
    done <"$changes_file"
  fi
  [ -n "$mb" ] && base="$mb"
fi

# L3 / L7: computed once mode is final; neither ever changes mode.
it_fanout="true"
case "$EVENT_NAME" in
  push) it_fanout="false" ;;
  pull_request)
    if [ "$PR_DRAFT" = "true" ] && [[ ",$LABELS," != *",full-ci,"* ]]; then it_fanout="false"; fi ;;
esac
selector_needed="true"
if [ "$EVENT_NAME" = "pull_request" ] && [ "$mode" = selective ] && [ "$fail_safe" -eq 0 ] &&
   [ "$e2e_input" -eq 0 ]; then
  selector_needed="false"
fi
# L11 last word: nothing above may defer or skip work on a promotion PR.
if [ "$promotion" -eq 1 ]; then mode="full"; it_fanout="true"; selector_needed="true"; fi

run_all="true"
if [ "$mode" = "selective" ] && [ "$SELECTIVE_ENABLED" = "true" ]; then
  run_all="false"
fi

# md_escape: values written to the step summary may derive from PR-controlled
# strings (SHAs from the event today; file names / selector reasons in phase
# 400). Strip anything that is not plainly safe, never trust the input.
md_escape() { printf '%s' "$1" | tr -c 'A-Za-z0-9._/:@ +,=-' '?' | cut -c1-200; }

emit() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; fi
  printf '%s=%s\n' "$1" "$2"
}
emit mode "$mode"
emit native "$native"
emit run_all "$run_all"
emit base "$base"
emit head "$head"
emit changed_count "$changed_count"
emit changes_dir "$OUT_DIR"
# Phase 400 sets the real selection size; "unknown" can never satisfy the
# ci-gate rule that mode=none needs an empty selection.
emit selection_count "${SELECTION_COUNT:-unknown}"
emit it_fanout "$it_fanout"
emit selector_needed "$selector_needed"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### CI plan"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| mode | \`$(md_escape "$mode")\` |"
    echo "| run_all | \`$(md_escape "$run_all")\` |"
    echo "| native | \`$(md_escape "$native")\` |"
    echo "| it_fanout | \`$(md_escape "$it_fanout")\` |"
    echo "| selector_needed | \`$(md_escape "$selector_needed")\` |"
    echo "| reason | $(md_escape "$reason") |"
    echo "| base (merge-base) | \`$(md_escape "${base:-n/a}")\` |"
    echo "| head | \`$(md_escape "${head:-n/a}")\` |"
    echo "| changed files | $(md_escape "$changed_count") |"
  } >>"$GITHUB_STEP_SUMMARY"
fi
