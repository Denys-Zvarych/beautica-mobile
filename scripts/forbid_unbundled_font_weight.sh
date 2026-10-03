#!/usr/bin/env bash
# Unbundled font-weight gate (phase 077 audit F3, 2026-10-03).
#
# THE REGRESSION THIS GUARDS
# --------------------------
# Only these faces are bundled under assets/fonts/ (runtime fetching is off,
# main.dart `allowRuntimeFetching = false`):
#     Comfortaa  w600 / w700
#     Nunito     w400 / w600 / w700 / w800
# A `FontWeight.w500` (or w100/w200/w300/w900) in lib/ asks google_fonts for a
# face that does not exist: the text renders at the nearest bundled weight (or
# the system font) instead of the weight the author wrote. Three such sites
# existed and rendered at the wrong weight unnoticed.
#
# THE RULE
# --------
# Zero unbundled weights under lib/ (excluding generated lib/api/), in any form:
#   FontWeight.w100|w200|w300|w500|w900
#   FontWeight(<100|200|300|500|900>)          (constructor, bare or `const`)
#   FontWeight.values[0|1|2|4|8]               (index: 0=w100 1=w200 2=w300 4=w500 8=w900)
#   FontWeight.lerp(...) with an unbundled constant argument (best effort: the
#     lerp call plus an unbundled FontWeight.wNNN on the same line)
# Comment-only lines are ignored. Use w400 / w600 / w700 / w800.
#
# Self-test:  ./scripts/forbid_unbundled_font_weight.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
PATTERN='FontWeight\.w(100|200|300|500|900)\b|FontWeight[[:space:]]*\([[:space:]]*(100|200|300|500|900)[[:space:]]*\)|FontWeight\.values[[:space:]]*\[[[:space:]]*[01248][[:space:]]*\]'

# run_scan <root>: "<path>:<line>:<text>" per offending, non-comment line.
run_scan() {
  local base="$1"
  (cd "$base" && grep -rEn --include='*.dart' --exclude-dir=api "$PATTERN" lib/ 2>/dev/null || true) |
    grep -Ev '^[^:]+:[0-9]+:[[:space:]]*//' || true
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/demo" "$tmp/lib/api"
  cat > "$tmp/lib/features/demo/bad.dart" <<'DART'
// FontWeight.w500 mentioned in a comment is fine
final a = TextStyle(fontWeight: FontWeight.w600);
final b = TextStyle(fontWeight: FontWeight.w500);
final c = TextStyle(fontWeight: FontWeight.w300);
final d = TextStyle(fontWeight: FontWeight.w900);
final e = TextStyle(fontWeight: FontWeight.w800);
final f = TextStyle(fontWeight: FontWeight(500));
final g = TextStyle(fontWeight: const FontWeight( 900 ));
final h = TextStyle(fontWeight: FontWeight.values[4]);
final i = TextStyle(fontWeight: FontWeight.values[1]);
final j = FontWeight.lerp(FontWeight.w400, FontWeight.w500, 0.5);
final k = TextStyle(fontWeight: FontWeight(600));
final l = TextStyle(fontWeight: FontWeight.values[5]);
final m = FontWeight.lerp(FontWeight.w400, FontWeight.w700, 0.5);
DART
  printf 'final g = FontWeight.w500;\n' > "$tmp/lib/api/gen.dart"
  out="$(run_scan "$tmp")"
  n="$(printf '%s\n' "$out" | grep -c . || true)"
  want="3 4 5 7 8 9 10 11"
  ok=1
  [ "$n" -eq 8 ] || ok=0
  for ln in $want; do grep -q "bad.dart:$ln:" <<< "$out" || ok=0; done
  if [ "$ok" -ne 1 ]; then
    echo "SELF-TEST FAIL: expected exactly bad.dart lines $want, got:"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST OK: forbid_unbundled_font_weight.sh"
  exit 0
fi

offenders="$(run_scan "$root")"
if [ -n "$offenders" ]; then
  echo "Unbundled FontWeight under lib/ (bundled: Comfortaa w600/w700, Nunito w400/w600/w700/w800):"
  echo "$offenders"
  echo
  echo "Use a bundled weight (usually FontWeight.w600) or a VelvetText token."
  exit 1
fi
exit 0
