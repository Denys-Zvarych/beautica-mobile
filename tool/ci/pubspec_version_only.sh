#!/usr/bin/env bash
# Version-only pubspec bump detector (release-bump PRs touch only the
# top-level `version:` line of pubspec.yaml). Sourced by ci_paths_guard.sh
# (skip the pubspec.yaml force-full) and plan.sh (skip the pubspec.yaml native
# flag). Base-owned like its callers. The selector applies the same rule in
# Dart (rules.yaml `version_only`, versionOnlyChange in selection.dart).
# Table-tested with real git fixtures by scripts/test/plan_sh_test.sh.
#
# pubspec_version_only <base> <head>: exit 0 iff `git diff <base> <head> --
# pubspec.yaml` removes exactly one top-level `version:` line, adds exactly one,
# and changes nothing else (no other line, no mode/type change, no add/delete,
# no "\ No newline" marker). Any other diff, an empty diff, or ANY git failure
# returns 1, so the caller treats pubspec.yaml exactly as before (fail closed).
# An indented `version:` (a dependency's) never matches: only column 0 does.
pubspec_version_only() {
  local out line minus=0 plus=0
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  out="$(git -c core.quotepath=false diff --no-color --no-ext-diff --no-textconv \
    --no-renames -U0 "$1" "$2" -- pubspec.yaml 2>/dev/null)" || return 1
  # An empty diff reads as one empty line -> the `*` arm -> 1.
  while IFS= read -r line; do
    case "$line" in
      'diff --git a/pubspec.yaml b/pubspec.yaml' | 'index '* | '--- a/pubspec.yaml' | '+++ b/pubspec.yaml' | '@@ '*) ;;
      -version:*) minus=$((minus + 1)) ;;
      +version:*) plus=$((plus + 1)) ;;
      *) return 1 ;;
    esac
  done <<<"$out"
  [ "$minus" -eq 1 ] && [ "$plus" -eq 1 ]
}
