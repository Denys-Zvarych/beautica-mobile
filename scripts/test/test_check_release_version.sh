#!/usr/bin/env bash
# Table-driven harness for scripts/check_release_version.sh (phase 409 D4 / T1).
# Each case copies the SHIPPED script into a throwaway git repo (fixture pubspec,
# a `main` that `refs/remotes/origin/main` points at, and an off-main commit) and
# runs it as CI does. A case passes only on the expected exit code AND the expected
# `::error::`/PASS text, so a rule that silently stops firing turns its row red.
# Phase 421 appends its `release` / `dev-pr` rows here.
#
# USAGE: ./scripts/test/test_check_release_version.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$HERE")/check_release_version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# mk <case> <pubspec-version-line...>: repo whose main commit carries the given
# pubspec body (printf %b, so \r and \n work). Prints "<root> <main-sha> <side-sha>".
mk() {
  local r="$TMP/$1"; shift
  mkdir -p "$r/scripts"
  cp "$SRC" "$r/scripts/check_release_version.sh"
  (
    cd "$r" || exit 1
    git init -q -b main .
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m root
    printf 'name: beautica_mobile\n%b\nenvironment:\n  sdk: ^3.11.0\n' "$1" > pubspec.yaml
    git add pubspec.yaml
    git -c user.email=t@t -c user.name=t commit -q -m main
    git update-ref refs/remotes/origin/main HEAD
    git checkout -q -b side
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m side
    git checkout -q main
  )
  printf '%s %s %s' "$r" "$(git -C "$r" rev-parse main)" "$(git -C "$r" rev-parse side)"
}

# check <name> <want_rc> <pattern> <root> [VAR=value ...]: run the copied script in
# mode `tag` with a clean env plus the given vars.
check() {
  local name="$1" want="$2" pat="$3" r="$4" out rc; shift 4
  out="$(cd "$r" && env -i PATH="$PATH" HOME="$HOME" "$@" \
    bash scripts/check_release_version.sh "${MODE:-tag}" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - exit %d, wanted %d\n%s\n' "$name" "$rc" "$want" "$out"; return
  fi
  if ! grep -aqF -- "$pat" <<< "$out"; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - output lacks %s\n%s\n' "$name" "$pat" "$out"; return
  fi
  PASS=$((PASS + 1)); printf '  PASS  %s\n' "$name"
}

echo "== mode tag: tag push =="
read -r r main side <<< "$(mk ok 'version: 1.1.0+2')"
check "match, on main (default origin/main)" 0 "PASS rule (c)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
check "match, GITHUB_SHA unset -> HEAD" 0 "PASS rule (c)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag
check "tag mismatch (build number)" 1 "::error::rule (a)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+3 GITHUB_SHA="$main"
check "tag without mobile- prefix" 1 "::error::rule (a)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=v1.1.0+2 GITHUB_SHA="$main"
check "tag with -hotfix.1 suffix" 1 "::error::rule (a)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2-hotfix.1 GITHUB_SHA="$main"
check "empty ref name" 1 "::error::rule (a)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_SHA="$main"
check "commit not on main" 1 "::error::rule (c)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$side"
check "main ref missing (shallow checkout)" 1 "::error::rule (c): main ref" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main" \
  RELEASE_MAIN_REF=origin/nope
check "unknown commit" 1 "::error::rule (c): commit" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag \
  GITHUB_SHA=0123456789012345678901234567890123456789

echo "== mode tag: ref type (a branch with a tag-like name must fail) =="
check "branch named like the tag (GITHUB_REF_TYPE=branch)" 1 "is a branch, not a tag" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=branch \
  GITHUB_REF=refs/heads/mobile-v1.1.0+2 GITHUB_SHA="$main"
check "branch named like the tag (GITHUB_REF only)" 1 "is not refs/tags/mobile-v1.1.0+2" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF=refs/heads/mobile-v1.1.0+2 \
  GITHUB_SHA="$main"
check "dry_run=false dispatch from a tag-named branch" 1 "is a branch, not a tag" "$r" \
  GITHUB_EVENT_NAME=workflow_dispatch DRY_RUN=false GITHUB_REF_NAME=mobile-v1.1.0+2 \
  GITHUB_REF_TYPE=branch GITHUB_REF=refs/heads/mobile-v1.1.0+2 GITHUB_SHA="$main"
check "ref type unknown fails closed" 1 "ref type unknown" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_SHA="$main"
check "type tag but GITHUB_REF disagrees" 1 "is not refs/tags/mobile-v1.1.0+2" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag \
  GITHUB_REF=refs/heads/mobile-v1.1.0+2 GITHUB_SHA="$main"
check "real tag (GITHUB_REF_TYPE=tag + GITHUB_REF=refs/tags/...) passes" 0 "PASS rule (a): tag mobile-v1.1.0+2" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag \
  GITHUB_REF=refs/tags/mobile-v1.1.0+2 GITHUB_SHA="$main"
check "real tag via GITHUB_REF only passes" 0 "PASS rule (c)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF=refs/tags/mobile-v1.1.0+2 \
  GITHUB_SHA="$main"

git -C "$r" -c user.email=t@t -c user.name=t tag -a -m rel mobile-v1.1.0+2 "$main"
check "annotated tag object as GITHUB_SHA is peeled" 0 "PASS rule (c)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag \
  GITHUB_SHA="$(git -C "$r" rev-parse refs/tags/mobile-v1.1.0+2)"

echo "== mode tag: malformed pubspec (rule b runs first) =="
read -r r main _ <<< "$(mk nob 'version: 1.1.0')"
check "no +B" 1 "::error::rule (b)" "$r" GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0 GITHUB_SHA="$main"
read -r r main _ <<< "$(mk hotfix 'version: 1.1.0-hotfix.1+2')"
check "-hotfix.1 pre-release suffix" 1 "::error::rule (b)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0-hotfix.1+2 GITHUB_SHA="$main"
read -r r main _ <<< "$(mk rc 'version: 1.1.0-rc1+2')"
check "-rc1 suffix" 1 "::error::rule (b)" "$r" GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0-rc1+2 GITHUB_SHA="$main"
read -r r main _ <<< "$(mk quoted "version: '1.1.0+2'")"
check "quoted version" 1 "::error::rule (b)" "$r" GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
read -r r main _ <<< "$(mk comment 'version: 1.1.0+2 # bump')"
check "trailing comment" 1 "::error::rule (b)" "$r" GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
read -r r main _ <<< "$(mk two 'version: 1.1.0+2\nversion: 1.2.0+3')"
check "two version lines" 1 "found 2" "$r" GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
read -r r main _ <<< "$(mk none 'description: x')"
check "no version line" 1 "found 0" "$r" GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
read -r r main _ <<< "$(mk indented '  version: 1.1.0+2')"
check "only an indented (non top-level) version" 1 "found 0" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
read -r r main _ <<< "$(mk crlf 'version: 1.1.0+2\r')"
check "CRLF pubspec still parses" 0 "PASS rule (c)" "$r" \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
check "missing pubspec" 1 "pubspec not found" "$r" PUBSPEC=nope.yaml \
  GITHUB_EVENT_NAME=push GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"

echo "== mode tag: workflow_dispatch =="
read -r r main side <<< "$(mk disp 'version: 1.1.0+2')"
check "dry run off main, branch ref: (a)+(c) skipped" 0 "::notice::" "$r" \
  GITHUB_EVENT_NAME=workflow_dispatch DRY_RUN=true GITHUB_REF_NAME=dev GITHUB_SHA="$side"
check "dry_run=false on a branch ref -> full rules" 1 "::error::rule (a)" "$r" \
  GITHUB_EVENT_NAME=workflow_dispatch DRY_RUN=false GITHUB_REF_NAME=dev GITHUB_SHA="$main"
check "dry_run=false on the release tag ref, on main" 0 "PASS rule (c)" "$r" \
  GITHUB_EVENT_NAME=workflow_dispatch DRY_RUN=false GITHUB_REF_NAME=mobile-v1.1.0+2 GITHUB_REF_TYPE=tag GITHUB_SHA="$main"
check "DRY_RUN=true on a push event is ignored" 1 "::error::rule (a)" "$r" \
  GITHUB_EVENT_NAME=push DRY_RUN=true GITHUB_REF_NAME=dev GITHUB_SHA="$main"
read -r r main _ <<< "$(mk dispbad 'version: 1.1.0')"
check "dry run still enforces rule (b)" 1 "::error::rule (b)" "$r" \
  GITHUB_EVENT_NAME=workflow_dispatch DRY_RUN=true GITHUB_REF_NAME=dev GITHUB_SHA="$main"

echo "== usage =="
read -r r _ _ <<< "$(mk usage 'version: 1.1.0+2')"
MODE=version check "mode version prints the version" 0 "1.1.0+2" "$r"
read -r r2 _ _ <<< "$(mk usagebad 'version: 1.1.0')"
MODE=version check "mode version enforces rule (b)" 1 "::error::rule (b)" "$r2"
MODE=bogus check "unknown mode" 2 "usage:" "$r"
MODE=release check "phase 421 mode not implemented yet" 2 "phase 421" "$r"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
