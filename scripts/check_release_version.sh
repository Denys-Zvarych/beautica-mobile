#!/usr/bin/env bash
# Release version checks — ONE script, ONE `version:` parser (ARCHITECTURE-mobile.md § 6.1).
#
#   ./scripts/check_release_version.sh <mode>
#
# Modes:
#   tag      Phase 409 D4 (owns phase 421 D5). First step of `.github/workflows/release-aab.yml`
#            job `guard`, which runs with NO environment, so a bad tag fails before any
#            secret is loaded.
#              (b) pubspec `version:` matches ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$
#              (a) GITHUB_REF_NAME == "mobile-v<pubspec version>" AND the ref is a TAG
#                  (GITHUB_REF_TYPE == tag, or GITHUB_REF starts with refs/tags/), so a
#                  BRANCH named mobile-v1.1.0+2 cannot pass
#              (c) the commit (GITHUB_SHA, else HEAD) is an ancestor of RELEASE_MAIN_REF
#                  (default origin/main), via `git merge-base --is-ancestor`.
#            On a workflow_dispatch DRY RUN (GITHUB_EVENT_NAME=workflow_dispatch and
#            DRY_RUN=true) (a) and (c) are skipped with a ::notice:: and (b) still runs.
#            A dispatch with DRY_RUN=false is treated like a tag push: all three rules run.
#   version  Rule (b) only; prints the pubspec version on stdout. The single `version:`
#            parser for other scripts (scripts/verify_release_aab.sh rule 2).
#   release, dev-pr
#            Reserved for phase 421 (D1-D3). Add them as new `mode_<name>` functions
#            below, reusing pubspec_version / check_format.
#
# Inputs come only from env: PUBSPEC (default pubspec.yaml), GITHUB_REF_NAME,
# GITHUB_REF_TYPE, GITHUB_REF, GITHUB_EVENT_NAME, DRY_RUN, GITHUB_SHA, RELEASE_MAIN_REF.
# Exit 0 = pass. Exit 1 = fail, with a `::error::` line naming the rule. Exit 2 = usage.
set -euo pipefail

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'
fail() { printf '::error::%s\n' "$1"; exit 1; }

# pubspec_version: sets PUBSPEC_VERSION to the value of the single top-level
# `version:` line. Fails (rule b) when there is not exactly one such line. It sets a
# global instead of printing so `fail` is never swallowed by a $(...) subshell.
PUBSPEC_VERSION=''
pubspec_version() {
  local f="${PUBSPEC:-pubspec.yaml}" lines n
  [ -f "$f" ] || fail "rule (b): pubspec not found: $f"
  lines="$(tr -d '\r' < "$f" | grep -E '^version:' || true)"
  n="$(printf '%s' "$lines" | grep -c '' || true)"
  [ "$n" -eq 1 ] || fail "rule (b): expected exactly one top-level 'version:' line in $f, found $n"
  PUBSPEC_VERSION="$(printf '%s' "$lines" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]+$//')"
}

# check_format <version>: rule (b). No quotes, no comments, no pre-release suffix.
check_format() {
  [[ "$1" =~ $VERSION_RE ]] \
    || fail "rule (b): pubspec version '$1' does not match X.Y.Z+B (^[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+\$)"
}

mode_tag() {
  local v ref ref_type full_ref event dry main sha expected
  pubspec_version
  v="$PUBSPEC_VERSION"
  check_format "$v"
  echo "PASS rule (b): pubspec version $v is X.Y.Z+B"

  event="${GITHUB_EVENT_NAME:-}"
  dry="${DRY_RUN:-false}"
  if [ "$event" = "workflow_dispatch" ] && [ "$dry" = "true" ]; then
    echo "::notice::workflow_dispatch dry run: tag rule (a) and main-ancestry rule (c) skipped"
    return 0
  fi

  ref="${GITHUB_REF_NAME:-}"
  expected="mobile-v$v"
  [ "$ref" = "$expected" ] \
    || fail "rule (a): ref '$ref' is not the release tag '$expected' (tag must equal mobile-v<pubspec version>)"
  # A branch can carry a tag-like name; only a tag ref counts. Both inputs must agree
  # when both are set (GitHub sets both on every run).
  ref_type="${GITHUB_REF_TYPE:-}"
  full_ref="${GITHUB_REF:-}"
  if [ -n "$ref_type" ] && [ "$ref_type" != "tag" ]; then
    fail "rule (a): ref '$ref' is a $ref_type, not a tag (GITHUB_REF_TYPE=$ref_type)"
  fi
  if [ -n "$full_ref" ] && [ "$full_ref" != "refs/tags/$ref" ]; then
    fail "rule (a): GITHUB_REF '$full_ref' is not refs/tags/$ref"
  fi
  [ -n "$ref_type" ] || [ -n "$full_ref" ] \
    || fail "rule (a): ref type unknown (neither GITHUB_REF_TYPE nor GITHUB_REF is set)"
  echo "PASS rule (a): tag $ref matches pubspec"

  main="${RELEASE_MAIN_REF:-origin/main}"
  sha="${GITHUB_SHA:-$(git rev-parse HEAD)}"
  git rev-parse --verify --quiet "$main^{commit}" >/dev/null \
    || fail "rule (c): main ref '$main' not found (checkout needs fetch-depth: 0)"
  git rev-parse --verify --quiet "$sha^{commit}" >/dev/null \
    || fail "rule (c): commit '$sha' not found"
  git merge-base --is-ancestor "$sha^{commit}" "$main^{commit}" \
    || fail "rule (c): commit $sha is not on $main (release tags go on main commits only)"
  echo "PASS rule (c): $sha is an ancestor of $main"
}

mode_version() {
  pubspec_version
  check_format "$PUBSPEC_VERSION"
  printf '%s\n' "$PUBSPEC_VERSION"
}

case "${1:-}" in
  tag) mode_tag ;;
  version) mode_version ;;
  release | dev-pr)
    echo "::error::mode '$1' is specified by phase 421 and not implemented yet" >&2
    exit 2 ;;
  *)
    echo "usage: $0 tag|version" >&2
    exit 2 ;;
esac
