#!/usr/bin/env bash
# Raw-ProviderContainer-with-header test gate (phase 361 audit, perf P2).
#
# THE LEAK THIS GUARDS
# --------------------
# Every header / shell now mounts the live notification bell. For an
# authenticated test session its REAL notifier starts a 60 s poll timer. A test
# that builds its OWN `ProviderContainer(` disposes it in `addTearDown` — AFTER
# flutter_test's pending-timer invariant — so the timer leaks and the test goes
# red (or, worse, passes on a lucky ordering). The fix lives in ONE place:
# `test/helpers/test_container.dart` -> `makeTestContainer(...)` pins the unread
# notifier to zero, installs the production retry policy and registers the
# dispose. Before the helper the rule lived only in a comment, and ~21 files
# followed it in two inconsistent styles.
#
# THE RULE
# --------
# A test file under `test/**` or `integration_test/**` that IMPORTS one of the
# header/shell widgets below must not contain a raw `ProviderContainer(` — use
# `makeTestContainer(...)`. A file that genuinely needs a raw container (it
# tests the live notifier on purpose) is listed in
# `scripts/.raw_container_with_header_allow` as `<path>:<line>   # reason`.
# LINE-level on purpose: a file-level exemption would let a genuinely new raw
# container slip in beside the legitimate one.
#
# HEADER WIDGETS: client_shell.dart, client_top_bar.dart, my_salons_screen.dart,
# salon_management_profile_screen.dart, salon_shell_screen.dart,
# notification_bell_button.dart.
# TRANSITIVE MOUNTERS (lib files that import a header, so importing them mounts
# the bell too): app_router.dart, move_admin_salon_screen.dart,
# staff_settings_screen.dart. `pumpRoutedApp` (test/helpers/pump_app.dart) takes
# a router the test builds, so it is covered through those imports, not listed.
# When a NEW lib file imports a header, add it to `header_import` below.
#
# CONSTRUCTORS MATCHED: `ProviderContainer(`, `.test(` and `.new(`.
#
# CI hard-gate (`.github/workflows/pr-validate.yml`); also runnable locally.
# Self-test:  ./scripts/forbid_raw_container_with_header.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
allow_file="$here/.raw_container_with_header_allow"

header_import='^[[:space:]]*import[[:space:]].*(client_shell|client_top_bar|my_salons_screen|salon_management_profile_screen|salon_shell_screen|notification_bell_button|app_router|move_admin_salon_screen|staff_settings_screen)[.]dart'
# Matches `ProviderContainer(`, `ProviderContainer.test(` and `ProviderContainer.new(`.
raw_container='ProviderContainer([.](test|new))?[(]'

# ---------------------------------------------------------------------------
# scan_file <path>
#   Emits "<path>:<line>:<text>" for each raw `ProviderContainer(` in a file
#   that imports a header widget. Genuine `//` comment lines are skipped.
# ---------------------------------------------------------------------------
scan_file() {
  grep -aEq "$header_import" "$1" || return 0
  awk -v file="$1" -v pat="$raw_container" '
    {
      trimmed = $0
      sub(/^[[:space:]]+/, "", trimmed)
      if (trimmed ~ /^[/][/]/) next
      if ($0 ~ pat) printf "%s:%d:%s\n", file, NR, $0
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp)"
  tmp2="$(mktemp)"
  trap 'rm -f "$tmp" "$tmp2"' EXIT
  printf '%s\n' \
    "import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';" \
    "  final c = ProviderContainer(overrides: []);" \
    "  // final d = ProviderContainer(overrides: []);" \
    "  final e = makeTestContainer(overrides: []);" \
    "  final f = ProviderContainer(" \
    "  final g = ProviderContainer.test(overrides: []);" \
    "  final h = ProviderContainer.new(overrides: []);" \
    > "$tmp"
  printf '%s\n' \
    "import 'package:beautica_mobile/features/auth/presentation/login_screen.dart';" \
    "  final c = ProviderContainer(overrides: []);" \
    > "$tmp2"
  tmp3="$(mktemp)"
  trap 'rm -f "$tmp" "$tmp2" "$tmp3"' EXIT
  printf '%s\n' \
    "import 'package:beautica_mobile/routing/app_router.dart';" \
    "  final c = ProviderContainer(overrides: []);" \
    > "$tmp3"
  out="$(scan_file "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  if [ "$flagged" -ne 4 ]; then
    echo "SELF-TEST FAIL: expected 4 offenders in the header-importing file, got $flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  if ! grep -q -- ':2:' <<< "$out" || ! grep -q -- ':5:' <<< "$out" \
    || ! grep -q -- ':6:' <<< "$out" || ! grep -q -- ':7:' <<< "$out"; then
    echo "SELF-TEST FAIL: expected lines 2, 5, 6 (.test) and 7 (.new) to be flagged"
    printf '%s\n' "$out"
    exit 1
  fi
  out3="$(scan_file "$tmp3")"
  if ! grep -q -- ':2:' <<< "$out3"; then
    echo "SELF-TEST FAIL: a raw container in a file importing app_router.dart (transitive header) must be flagged"
    printf '%s\n' "$out3"
    exit 1
  fi
  out2="$(scan_file "$tmp2")"
  if [ -n "$out2" ]; then
    echo "SELF-TEST FAIL: a file WITHOUT a header import must not be flagged"
    printf '%s\n' "$out2"
    exit 1
  fi
  echo "SELF-TEST PASS: raw containers flagged in a header-importing file; commented-out line, makeTestContainer and header-free file are clean."
  echo "SELF-TEST OK: forbid_raw_container_with_header.sh"
  exit 0
fi

# Load the FILE:LINE allow-list (`#` comments and blank lines ignored).
declare -A ALLOWED=()
if [ -f "$allow_file" ]; then
  while IFS= read -r raw; do
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && ALLOWED["$line"]=1
  done < "$allow_file"
fi

mapfile -t files < <(
  {
    find test -type f -name '*.dart' 2>/dev/null || true
    find integration_test -type f -name '*.dart' 2>/dev/null || true
  } | sort -u
)

[ "${#files[@]}" -eq 0 ] && exit 0

offenders=""
for f in "${files[@]}"; do
  hits="$(scan_file "$f")"
  [ -z "$hits" ] && continue
  while IFS= read -r hit; do
    key="${hit%%:*}:$(cut -d: -f2 <<< "$hit")"
    [ -n "${ALLOWED[$key]:-}" ] && continue
    offenders+="$hit"$'\n'
  done <<< "$hits"
done
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "Raw ProviderContainer( in a test that imports a header/shell widget:"
  echo "$offenders"
  echo
  echo "A header mounts the live notification bell; a raw container leaves its"
  echo "60 s poll timer running past the pending-timer check. Build the container"
  echo "with the shared helper instead (it pins unread to zero, installs the"
  echo "production retry policy and registers the dispose):"
  echo "    import '<rel>/helpers/test_container.dart';"
  echo "    final container = makeTestContainer(overrides: [...]);"
  echo "A test that genuinely needs a raw container is listed as <path>:<line> in"
  echo "scripts/.raw_container_with_header_allow."
  exit 1
fi

exit 0
