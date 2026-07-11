#!/usr/bin/env bash
# VelvetText font-size consolidation gate (2026-07-10 refactor ratchet).
#
# THE REGRESSION THIS GUARDS
# --------------------------
# 212 inline `fontSize:` sites across ~60 lib/features/** files were replaced
# with 116 cached tokens on `lib/core/theme/velvet_text.dart` (VelvetText).
# The consolidation is visually zero-change (the golden suites are the parity
# proof — nothing regenerated), but nothing STRUCTURAL stops a new screen from
# writing `TextStyle(fontSize: 14)` / `.copyWith(fontSize: 14)` again and
# silently re-fragmenting the scale. THIS gate is that structural ratchet: any
# `fontSize:` under lib/features/** must either be a VelvetText token (i.e. no
# inline `fontSize:` at all) or be one of the explicitly-allowlisted legitimate
# sites (runtime-computed values or widget-constructor params that genuinely
# cannot be a compile-time token).
#
# THE RULE
# --------
# Zero inline `fontSize:` under lib/features/** EXCEPT the file:line entries in
# scripts/.inline_fontsize_allow. Line-level allowlist (a whole-file exemption
# would let a new literal slip in beside a legitimate one). The migrated files
# are frozen, so the line numbers are stable; if a listed file is edited and a
# line shifts, the gate fails loudly and the allowlist line is updated — the
# intended ratchet behaviour. New inline sizes must instead be a token:
#     final l10n = ...;                       // unchanged
#     Text('...', style: VelvetText.<token>())
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_inline_fontsize.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
default_allow="$here/.inline_fontsize_allow"

# ---------------------------------------------------------------------------
# run_scan <features_dir> <allow_file>
#   Emits "<path>:<line>:<text>" for every `fontSize:` occurrence under
#   <features_dir> whose "<path>:<line>" key is NOT in <allow_file>. The
#   allow-file uses one "path:line" per line; text after `#` is a reason
#   comment and all whitespace is stripped before keying.
# ---------------------------------------------------------------------------
run_scan() {
  local scan_dir="$1" allow="$2"
  local -A ALLOW=()
  if [ -f "$allow" ]; then
    local raw stripped key
    while IFS= read -r raw; do
      stripped="${raw%%#*}"
      key="$(printf '%s' "$stripped" | tr -d '[:space:]')"
      [ -n "$key" ] && ALLOW["$key"]=1
    done < "$allow"
  fi

  local h loc rest lineno
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    loc="${h%%:*}"            # repo-relative path
    rest="${h#*:}"
    lineno="${rest%%:*}"      # line number
    [ -n "${ALLOW["$loc:$lineno"]:-}" ] && continue
    printf '%s\n' "$h"
  done < <(
    cd "$root" && grep -rEn 'fontSize:' lib/features/ 2>/dev/null | sort || true
  )
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a features tree + allowlist and assert that only
# the un-allowlisted inline site is flagged.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/demo"

  # good.dart line 1 = an allowlisted runtime-computed site; line 2 = a NEW
  # inline literal that must be flagged.
  cat > "$tmp/lib/features/demo/good.dart" <<'EOF'
      fontSize: diameter * 0.44,
      style: TextStyle(fontSize: 14),
EOF

  cat > "$tmp/allow" <<'EOF'
# reason comments allowed
lib/features/demo/good.dart:1   # runtime-computed, legit
EOF

  # run_scan resolves paths against $root; point it at the temp tree.
  root="$tmp"
  out="$(run_scan "$tmp/lib/features" "$tmp/allow")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  if [ "$flagged" -ne 1 ] || ! printf '%s' "$out" | grep -q 'good.dart:2'; then
    echo "SELF-TEST FAIL: expected exactly line 2 flagged, got:"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: allowlisted line 1 is exempt; the new inline"
  echo "                TextStyle(fontSize: 14) on line 2 is flagged."
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root/lib/features" "$default_allow")"

if [ -n "$offenders" ]; then
  echo "Inline fontSize: found under lib/features/** (not on the allowlist):"
  echo "$offenders"
  echo
  echo "The VelvetText consolidation moved every inline font size onto a cached"
  echo "token in lib/core/theme/velvet_text.dart. Do NOT re-introduce an inline"
  echo "TextStyle(fontSize: N) / .copyWith(fontSize: N). Instead use (or add) a"
  echo "VelvetText token:"
  echo "    Text('...', style: VelvetText.<token>())"
  echo
  echo "If this site is GENUINELY runtime-computed (value depends on layout at"
  echo "build time) or a widget-constructor param that cannot be a token, add"
  echo "its path:line to scripts/.inline_fontsize_allow with a one-line reason."
  exit 1
fi

exit 0
