#!/usr/bin/env bash
# Direct-Navigator gate (phase 1.4) — go_router-only navigation in feature
# code. Moved VERBATIM out of the inline `pr-validate.yml` step (2026-11-26)
# so it is versioned, self-tested and run by scripts/verify_guards.sh.
#
# THE RULE
# --------
# Under lib/features/, no `Navigator.push`, `Navigator.pop` or `Navigator.of`
# — navigation goes through go_router (`context.go(RouteNames.x)`, and the
# root context via `GoRouter.of(context).routerDelegate.navigatorKey`, see
# lib/features/notifications/presentation/push_tap_dispatcher.dart).
# A line whose FIRST non-whitespace characters are a comment (`//`, `/*`, `*`)
# is skipped: ported-screen headers document the preview's imperative
# Navigator → go_router swap. Why: docs/ci/static-guards.md#direct-navigator
#
# Usage:
#   ./scripts/forbid_direct_navigator.sh              scan lib/features/
#   ./scripts/forbid_direct_navigator.sh --self-test  prove it fails on a planted violation

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# check <root> : the original CI step, run from <root>. Exit 1 on a match.
check() {
  local root="$1" MATCHES
  MATCHES=$(cd "$root" && grep -rnE 'Navigator\.(push|pop|of)\b' lib/features/ 2>/dev/null | awk -F: '
    {
      content = $0
      sub(/^[^:]*:[0-9]+:/, "", content)
      trimmed = content
      sub(/^[ \t]*/, "", trimmed)
      if (trimmed !~ /^(\/\/|\/\*|\*)/) print $0
    }
  ') || true
  if [ -n "$MATCHES" ]; then
    echo 'Direct Navigator usage found in lib/features/ — use context.go(RouteNames.x) instead'
    echo "$MATCHES"
    return 1
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/x"
  printf '%s\n' \
    "// Navigator.push(context, r) in a comment" \
    "  /* Navigator.of(context).pop() */" \
    "   * Navigator.pop(context) in a doc block" \
    "void a(BuildContext context) => context.go('/a');" \
    > "$tmp/lib/features/x/clean.dart"
  if ! check "$tmp" >/dev/null; then
    echo "SELF-TEST FAIL: commented-out lines flagged" >&2; exit 1
  fi
  printf '%s\n' \
    "void b(BuildContext context) => Navigator.of(context, rootNavigator: true);" \
    > "$tmp/lib/features/x/bad.dart"
  if check "$tmp" >/dev/null; then
    echo "SELF-TEST FAIL: planted Navigator.of not rejected" >&2; exit 1
  fi
  n="$(check "$tmp" | grep -c 'lib/features/x/' || true)"
  if [ "$n" -ne 1 ]; then
    echo "SELF-TEST FAIL: expected exactly 1 flagged line, got $n" >&2; exit 1
  fi
  echo "SELF-TEST OK: $(basename "$0")"
  exit 0
fi

if check "$repo"; then
  echo "forbid_direct_navigator: OK"
else
  exit 1
fi
