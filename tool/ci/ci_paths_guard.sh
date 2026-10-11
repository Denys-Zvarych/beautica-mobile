#!/usr/bin/env bash
# CI-paths guard (phase 397; extracted from the `plan` job's
# `Guard - CI machinery changes force full` step by phase 402 D14).
#
# Independent of the planner/selector (which a PR could try to subvert): plain
# shell over the merge-base diff. Any change to CI machinery or test-execution
# config forces mode=full regardless of what the planner decided. Base-owned:
# the plan step runs the trusted/ (base commit) copy, and the PR copy only while
# the base lacks this file (bootstrap, with a ::warning::). cwd = the PR checkout.
#
# Inputs (env): BASE_SHA, HEAD_SHA (the checked-out commit), RUNNER_TEMP,
#   GITHUB_OUTPUT. The working directory is the PR checkout.
# Outputs: `mode=full` + `run_all=true` to $GITHUB_OUTPUT when forced; nothing
#   otherwise. Exit 1 (fail closed) on a forbidden path in the diff.
#
# Sourcing this file only defines is_forced / is_forbidden (table-tested by
# scripts/test/plan_sh_test.sh; parity with rules.yaml in guard_parity_test.dart).

force() { { echo "mode=full"; echo "run_all=true"; } >> "$GITHUB_OUTPUT"; echo "::notice::mode forced to full: $1"; }

# CI machinery AND test-execution config. Keep one `<globs>) return N ;;` arm
# per line: guard_parity_test.dart parses them.
is_forced() {
  case "$1" in
    scripts/perf/*) return 1 ;;
    .github/* | tool/ci/* | scripts/*) return 0 ;;
    trusted | trusted/*) return 0 ;;
    analysis_options.yaml | pubspec.yaml | pubspec.lock | dart_test.yaml | build.yaml) return 0 ;;
    test/flutter_test_config.dart | test_driver/*) return 0 ;;
    test/helpers/* | test/ci/* | integration_test/support/*) return 0 ;;
    android/gradle/wrapper/* | android/gradle.properties) return 0 ;;
  esac
  return 1
}

# Paths that must never appear in a PR diff: build output / tool cache
# (gitignored; a committed one is a planted file or symlink aimed at
# CI output paths) and a top-level trusted/ (the integration job checks
# the base commit out at that name; a PR-made one would shadow it). Fail the plan rather than force-full: there is no
# legitimate case, so red is the right signal. Also table-tested.
is_forbidden() {
  case "$1" in
    build/* | .dart_tool/* | trusted | trusted/*) return 0 ;;
  esac
  return 1
}

main() {
  set -euo pipefail
  # NUL-delimited + unquoted (core.quotepath=false): a non-ASCII or
  # odd path must reach is_forced verbatim, not as an octal-quoted string.
  local raw="$RUNNER_TEMP/guard-files.bin" mb f forced=0
  if ! mb="$(git merge-base "$BASE_SHA" "$HEAD_SHA")" ||
     ! git -c core.quotepath=false diff -z --no-renames --name-only "$mb" "$HEAD_SHA" >"$raw"; then
    force "diff unavailable"; exit 0
  fi
  while IFS= read -r -d '' f; do
    if is_forbidden "$f"; then
      echo "::error::PR diff contains a build artefact path (path withheld: PR-controlled); build/, .dart_tool/ and trusted/ are never committed (fail closed)"
      exit 1
    fi
    if is_forced "$f"; then forced=1; fi
  done <"$raw"
  if [ "$forced" -eq 1 ]; then force "CI machinery / test config changed"; fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
