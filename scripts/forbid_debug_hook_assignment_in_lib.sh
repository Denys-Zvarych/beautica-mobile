#!/usr/bin/env bash
# Phase 075 gate — test-only debug hooks must never be ASSIGNED in lib/.
#
# `StartupTrace.debugRecorder` and `AppConfig.debugOnAssertSecureUrl` are
# assert-only `@visibleForTesting` seams: tests install them, production code
# only declares and invokes them. An assignment under lib/ would let a debug
# build run attacker/dev-supplied code inside the secure-URL guard or the boot
# trace. Declarations (`static ... debugRecorder;`) carry no `=` and so never
# match; `==` comparisons are excluded.
#
# Usage:
#   ./scripts/forbid_debug_hook_assignment_in_lib.sh              scan lib/
#   ./scripts/forbid_debug_hook_assignment_in_lib.sh --self-test  prove it fails on a planted assignment

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

# scan <root> : prints FILE:LINE:text for each assignment under <root>/lib.
scan() {
  grep -a -rnE --include='*.dart' \
    '\b(debugRecorder|debugOnAssertSecureUrl)[[:space:]]*=([^=]|$)' "$1/lib" 2>/dev/null || true
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib"
  printf '%s\n' '  static void Function()? debugOnAssertSecureUrl;' \
    '  static StartupTraceRecorder? debugRecorder;' \
    '  if (debugRecorder == null) {}' > "$tmp/lib/clean.dart"
  if [ -n "$(scan "$tmp")" ]; then
    echo "SELF-TEST FAIL: declarations / == flagged" >&2; exit 1
  fi
  printf '%s\n' 'void f() { StartupTrace.debugRecorder = (a, b) {}; }' > "$tmp/lib/bad1.dart"
  printf '%s\n' 'void g() { AppConfig.debugOnAssertSecureUrl=() {}; }' > "$tmp/lib/bad2.dart"
  n="$(scan "$tmp" | wc -l)"
  if [ "$n" -ne 2 ]; then
    echo "SELF-TEST FAIL: expected 2 planted assignments detected, got $n" >&2; exit 1
  fi
  echo "SELF-TEST OK: $(basename "$0")"
  exit 0
fi

hits="$(scan "$repo")"
if [ -n "$hits" ]; then
  echo "FORBIDDEN: test-only debug hook assigned in lib/:" >&2
  printf '  %s\n' "$hits" >&2
  echo "Assign these seams from test/ only (phase 075)." >&2
  exit 1
fi
echo "forbid_debug_hook_assignment_in_lib: OK"
