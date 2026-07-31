#!/usr/bin/env bash
# Phase 1.2 spacing-scale gate.
#
# Beautica's design system locks padding/margin/inset values to the
# tokens exposed by `lib/core/theme/app_spacing.dart` (`AppSpacing.xxs` …
# `AppSpacing.xxl`) and `lib/core/theme/velvet_geometry.dart`
# (`VelvetSpacing.xs` … `VelvetSpacing.xxl`). Every `EdgeInsets*`
# constructor under `lib/` MUST reference one of those constants — raw
# numeric literals are forbidden so designers and engineers share the same
# spacing vocabulary and so theme refactors don't drift.
#
# WHAT THIS ACTUALLY CATCHES (narrower than you might assume)
# -----------------------------------------------------------
# The pattern requires the numeric literal to sit IMMEDIATELY after the open
# paren, so only POSITIONAL leading literals are flagged:
#
#   EdgeInsets.all(16)                      ← FLAGGED
#   EdgeInsets.fromLTRB(4, 0, 4, 0)         ← FLAGGED
#   EdgeInsets.fromSTEB(4, 0, 4, 0)         ← FLAGGED
#   EdgeInsetsDirectional.all(8)            ← FLAGGED
#
# A literal behind a NAMED parameter is NOT matched:
#
#   EdgeInsets.symmetric(horizontal: 16)    ← not flagged
#   EdgeInsets.only(top: 8)                 ← not flagged
#
# This is a deliberate record of current behaviour, not an endorsement: the
# header used to claim the named-parameter forms were covered, and they never
# were. As of 2026-07-31 there are ~53 such sites live under `lib/`, so
# widening the pattern is a real remediation task with its own diff — not a
# comment fix. The `--self-test` fixture below PINS both halves (flagged and
# not-flagged) so the true contract is executable rather than asserted in prose,
# and so a future widening has to update the fixture consciously.
#
# Exemption is line-level: any line already routing through `AppSpacing.` or
# `VelvetSpacing.` is filtered out before the offender check, so e.g.
# `EdgeInsets.all(AppSpacing.md)` and `EdgeInsets.all(VelvetSpacing.md)` both
# pass. Note this is a whole-LINE filter — a line mixing a token and a literal
# (`EdgeInsets.fromLTRB(4, AppSpacing.md, 4, 0)`) is exempted by the token.
#
# This script is the CI hard-gate (run from `.github/workflows/pr-validate.yml`)
# and can also be invoked locally before pushing.
# Self-test:  ./scripts/forbid_magic_padding.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# ---------------------------------------------------------------------------
# run_scan <lib_dir>
#   Emits "<path>:<line>:<text>" for every EdgeInsets* constructor under
#   <lib_dir> that opens with a raw numeric literal and does not route through
#   AppSpacing./VelvetSpacing. on the same line. Empty output == clean.
# ---------------------------------------------------------------------------
run_scan() {
  local scan_dir="$1"
  grep -rEn \
      "EdgeInsets(Directional)?\.(all|symmetric|fromLTRB|fromSTEB|only)\(\s*[0-9]" \
      "$scan_dir" 2>/dev/null \
    | grep -v "AppSpacing\." \
    | grep -v "VelvetSpacing\." \
    || true
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a lib tree holding both a violation the guard MUST
# flag and the token/named-param forms it MUST pass, then assert exactly the
# expected set comes back. Verifies the guard goes red on the bad fixture —
# an always-green guard is worse than no guard.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/demo"

  # MUST be flagged: positional raw literals.
  cat > "$tmp/lib/features/demo/bad.dart" <<'EOF'
      padding: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      margin: const EdgeInsetsDirectional.all(8),
EOF

  # MUST pass. Three distinct reasons, deliberately kept apart:
  #  1-2. Token-routed and never matched by the pattern at all (the literal
  #       position holds `AppSpacing.`/`VelvetSpacing.`, not a digit).
  #  3-4. Matched by the pattern (they OPEN with a `0`) and rescued ONLY by the
  #       line-level token exemption — a leading zero beside real tokens is not
  #       a magic value. These two are what make the `grep -v AppSpacing.` /
  #       `grep -v VelvetSpacing.` filters load-bearing in this self-test;
  #       without them, deleting either filter still passed.
  #  5-6. The named-parameter forms this guard does not (yet) cover — see the
  #       header. If a future widening starts catching them, this fixture fails
  #       and forces the header's contract to be updated with it.
  cat > "$tmp/lib/features/demo/good.dart" <<'EOF'
      padding: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.md),
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(0, VelvetSpacing.md, 0, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(top: 8),
EOF

  out="$(run_scan "$tmp/lib")"
  flagged="$(printf '%s' "$out" | grep -c . || true)"

  fail=0
  if [ "$flagged" -ne 3 ]; then
    echo "SELF-TEST FAIL: expected exactly 3 flagged lines, got $flagged:"
    printf '%s\n' "$out"
    fail=1
  fi
  if printf '%s' "$out" | grep -q 'good\.dart'; then
    echo "SELF-TEST FAIL: a good.dart line was flagged (false positive):"
    printf '%s\n' "$out" | grep 'good\.dart'
    fail=1
  fi
  for want in 'bad.dart:1' 'bad.dart:2' 'bad.dart:3'; do
    if ! printf '%s' "$out" | grep -q "$want"; then
      echo "SELF-TEST FAIL: expected $want to be flagged, it was not."
      fail=1
    fi
  done
  [ "$fail" -eq 0 ] || exit 1

  echo "SELF-TEST PASS: 3 positional raw-literal EdgeInsets flagged;"
  echo "                AppSpacing./VelvetSpacing. lines exempt; the"
  echo "                named-parameter forms remain out of scope (see header)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root/lib")"

if [ -n "$offenders" ]; then
  echo "Raw numeric EdgeInsets found under lib/ (spacing-scale gate):"
  echo "$offenders"
  echo
  echo "Padding/margin values are locked to the design-system scale. Replace the"
  echo "literal with a token from lib/core/theme/app_spacing.dart (AppSpacing.*)"
  echo "or lib/core/theme/velvet_geometry.dart (VelvetSpacing.*):"
  echo "    padding: const EdgeInsets.all(AppSpacing.md)"
  exit 1
fi

exit 0
