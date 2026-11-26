#!/usr/bin/env bash
# MS1 gate — no SharedPreferences in feature code; tokens and PII go to
# flutter_secure_storage only. Moved out of the inline `pr-validate.yml` step
# (2026-11-26) so it is versioned, self-tested and run by
# scripts/verify_guards.sh. Why: docs/ci/static-guards.md#shared-preferences
#
# ONE FIX vs the inline step: its comment filter was `grep -v "^\s*//"`
# applied to `grep -r` output, whose lines start with `path:`, so it never
# matched and a commented mention was flagged. Comment-only lines (first
# non-whitespace `//`, `/*`, `*`) are now skipped with the same awk filter
# as forbid_direct_navigator.sh. Real uses are flagged exactly as before.
#
# Usage:
#   ./scripts/forbid_shared_preferences.sh              scan lib/features/
#   ./scripts/forbid_shared_preferences.sh --self-test  prove it fails on a planted violation

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# check <root> : exit 1 on a SharedPreferences use under <root>/lib/features.
check() {
  local root="$1" MATCHES
  MATCHES=$(cd "$root" && grep -rnE "SharedPreferences|shared_preferences" lib/features/ 2>/dev/null | awk -F: '
    {
      content = $0
      sub(/^[^:]*:[0-9]+:/, "", content)
      trimmed = content
      sub(/^[ \t]*/, "", trimmed)
      if (trimmed !~ /^(\/\/|\/\*|\*)/) print $0
    }
  ') || true
  if [ -n "$MATCHES" ]; then
    echo "SharedPreferences found in lib/features/ — use SecureStorage instead"
    echo "$MATCHES"
    return 1
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/x"
  printf '%s\n' \
    "// Never SharedPreferences here (MS1)." \
    "  /* import 'package:shared_preferences/shared_preferences.dart'; */" \
    "final String token = await secureStorage.read('t');" \
    > "$tmp/lib/features/x/clean.dart"
  if ! check "$tmp" >/dev/null; then
    echo "SELF-TEST FAIL: commented-out lines flagged" >&2; exit 1
  fi
  printf '%s\n' \
    "import 'package:shared_preferences/shared_preferences.dart';" \
    "final prefs = await SharedPreferences.getInstance();" \
    > "$tmp/lib/features/x/bad.dart"
  if check "$tmp" >/dev/null; then
    echo "SELF-TEST FAIL: planted SharedPreferences not rejected" >&2; exit 1
  fi
  n="$(check "$tmp" | grep -c 'lib/features/x/' || true)"
  if [ "$n" -ne 2 ]; then
    echo "SELF-TEST FAIL: expected exactly 2 flagged lines, got $n" >&2; exit 1
  fi
  echo "SELF-TEST OK: $(basename "$0")"
  exit 0
fi

if check "$repo"; then
  echo "forbid_shared_preferences: OK"
else
  exit 1
fi
