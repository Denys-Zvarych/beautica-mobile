#!/usr/bin/env bash
# Phase 066 gate — no Firebase client config may be tracked by git.
#
# google-services.json (Android) and GoogleService-Info.plist (iOS) are
# injected at build time by the repo-root deploy scripts from
# ${BEAUTICA_SECRETS_DIR:-<repo-root>/../SecretsBeautica}. The repo is public:
# nothing Firebase-specific may be committed. `.gitignore` already covers the
# names, but `git add -f` bypasses it — this gate checks the index itself, by
# name (incl. renamed copies such as "google-services (1).json") and by content
# (a tracked file holding both "project_info" and an api key field).
#
# Usage:
#   ./scripts/forbid_google_services_json.sh              check tracked files
#   ./scripts/forbid_google_services_json.sh --self-test  prove it fails on
#                                                         staged dummy files

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# Prints offending tracked paths for the index selected by GIT_INDEX_FILE.
scan() {
  git -C "$repo" ls-files -- '*google-services*.json' '*GoogleService-Info*.plist'
  # Content tell-tale: files containing "project_info" AND an api key field.
  local with_info
  with_info="$(git -C "$repo" grep -l --cached -e '"project_info"' -- \
    ':!scripts/forbid_google_services_json.sh' ':!test/ci' 2>/dev/null || true)"
  if [ -n "$with_info" ]; then
    local f
    while IFS= read -r f; do
      if git -C "$repo" grep -q --cached -e '"api_key"' -e '"current_key"' -- "$f" 2>/dev/null; then
        printf '%s\n' "$f"
      fi
    done <<<"$with_info"
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  real_index="$(git -C "$repo" rev-parse --git-path index)"
  case "$real_index" in /*) ;; *) real_index="$repo/$real_index" ;; esac
  stage_and_expect_fail() {
    local path="$1" body="$2" blob
    cp "$real_index" "$tmp/index"
    blob="$(printf '%s' "$body" | git -C "$repo" hash-object -w --stdin)"
    GIT_INDEX_FILE="$tmp/index" git -C "$repo" update-index --add \
      --cacheinfo "100644,$blob,$path"
    if [ -z "$(GIT_INDEX_FILE="$tmp/index" scan)" ]; then
      echo "SELF-TEST FAIL: staged dummy '$path' not detected" >&2
      exit 1
    fi
  }
  stage_and_expect_fail 'android/app/google-services.json' '{}'
  stage_and_expect_fail 'ios/Runner/GoogleService-Info.plist' '<plist/>'
  stage_and_expect_fail 'android/app/google-services (1).json' '{}'
  stage_and_expect_fail 'docs/innocent.txt' '{"project_info":{},"api_key":[{"current_key":"x"}]}'
  echo "SELF-TEST OK: $(basename "$0")"
  exit 0
fi

hits="$(scan | sort -u)"
if [ -n "$hits" ]; then
  echo "FORBIDDEN: Firebase client config is tracked by git:" >&2
  printf '  %s\n' "$hits" >&2
  echo "Remove with: git rm --cached <path>. Config is injected at build time (phase 066)." >&2
  exit 1
fi
echo "forbid_google_services_json: OK"
