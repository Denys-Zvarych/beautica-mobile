#!/usr/bin/env bash
# Table-driven self-test of tool/ci/resolve_selection.sh (phase 400 D1/D7):
# every selector failure shape resolves to mode=full, never selective/none.
# Prints `SELF-TEST OK: resolve_selection_test.sh` on success.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
res="$repo/tool/ci/resolve_selection.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
rc=0
echo "resolve_selection_test"

# case_res <name> <selector-rc> <json-body|-(no file)> <expect k=v ...>
case_res() {
  local name="$1" src="$2" body="$3"; shift 3
  local d="$tmp/$RANDOM$RANDOM" out kv ok=1
  mkdir -p "$d"
  [ "$body" = - ] || printf '%s' "$body" >"$d/selection.json"
  out="$(env -u GITHUB_OUTPUT GITHUB_STEP_SUMMARY="$d/summary.md" bash "$res" "$src" "$d/selection.json" 2>&1)" || {
    printf '  FAIL  %s (script exited non-zero)\n' "$name"; rc=1; return; }
  for kv in "$@"; do
    grep -qx -- "$kv" <<<"$out" || { ok=0; printf '  FAIL  %s (missing %s)\n' "$name" "$kv"; }
  done
  if [ "$ok" -eq 1 ]; then printf '  PASS  %s\n' "$name"; else printf '%s\n' "$out" | sed 's/^/        /'; rc=1; fi
  LAST_DIR="$d"
}

sel='{"mode":"selective","unit":["test/a_test.dart","test/b_test.dart"],"golden":["test/golden/g_test.dart"],"tz_sweep":["test/core/time/t_test.dart"],"integration":["integration_test/f_test.dart"],"reasons":[]}'
case_res "valid selective -> selective + counts" 0 "$sel" \
  mode=selective run_all=false unit_count=2 golden_count=1 tz_count=1 integration_count=1 selection_count=5 test_count=4 kyiv_count=0
if [ "$(cat "$LAST_DIR/unit.txt")" = "$(printf 'test/a_test.dart\ntest/b_test.dart')" ] &&
   [ "$(cat "$LAST_DIR/golden.txt")" = "test/golden/g_test.dart" ] &&
   [ "$(cat "$LAST_DIR/tz_sweep.txt")" = "test/core/time/t_test.dart" ] &&
   [ "$(cat "$LAST_DIR/integration.txt")" = "integration_test/f_test.dart" ]; then
  echo "  PASS  list files rewritten from the JSON"
else
  echo "  FAIL  list files do not match the JSON"; rc=1
fi
if grep -q 'test/a_test.dart' "$LAST_DIR/summary.md" && grep -q '| unit | 2 |' "$LAST_DIR/summary.md"; then
  echo "  PASS  summary shows counts + paths"
else
  echo "  FAIL  summary"; rc=1
fi

# Stale list files planted by anything else are overwritten, not trusted.
d2="$tmp/stale"; mkdir -p "$d2"; printf '%s' "$sel" >"$d2/selection.json"; printf 'test/evil_test.dart\n' >"$d2/unit.txt"
env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY bash "$res" 0 "$d2/selection.json" >/dev/null
if grep -q evil "$d2/unit.txt"; then echo "  FAIL  stale unit.txt kept"; rc=1; else echo "  PASS  stale unit.txt replaced"; fi

# kyiv_count (phase 400 final pass): 1 iff the DST day-rail file is in the tz
# list (exact line), the base-owned source of the owed tz-kyiv stream.
rail=test/features/booking/presentation/bookings_day_rail_test.dart
kyiv="$(jq -nc --arg r "$rail" '{mode:"selective",unit:[$r],golden:[],tz_sweep:[$r,"test/core/time/t_test.dart"],integration:[],reasons:[]}')"
case_res "rail in tz list -> kyiv_count=1" 0 "$kyiv" mode=selective tz_count=2 kyiv_count=1
# Rail only in unit (not tz) and a near-miss path in tz: neither counts.
nokyiv="$(jq -nc --arg r "$rail" '{mode:"selective",unit:[$r],golden:[],tz_sweep:["test/features/booking/presentation/bookings_day_rail_test.dart.bak_test.dart","test/x/\($r)"],integration:[],reasons:[]}')"
case_res "tz list without the rail -> kyiv_count=0" 0 "$nokyiv" mode=selective tz_count=2 kyiv_count=0

none='{"mode":"none","unit":[],"golden":[],"tz_sweep":[],"integration":[],"reasons":[{"path":"docs/x.md","rule":"none: docs/**"}]}'
case_res "valid none -> none, selection 0" 0 "$none" mode=none run_all=false selection_count=0 test_count=0 kyiv_count=0

full_v='{"mode":"full","unit":[],"golden":[],"tz_sweep":[],"integration":[],"reasons":[{"path":"scripts/x.sh","rule":"full: scripts/**"},{"path":"lib/a.dart","rule":"seed"}]}'
case_res "selector says full -> full" 0 "$full_v" mode=full run_all=true selection_count=unknown test_count=unknown kyiv_count=0
if grep -q 'scripts/x.sh: full: scripts/' "$LAST_DIR/summary.md" && ! grep -q 'lib/a.dart: seed' "$LAST_DIR/summary.md"; then
  echo "  PASS  summary lists only the full reasons"
else
  echo "  FAIL  full reasons in summary"; rc=1
fi
thr='{"mode":"full","unit":[],"golden":[],"tz_sweep":[],"integration":[],"reasons":[{"path":"*","rule":"unit selection 700/800 > 60% -> full"}]}'
case_res "threshold full -> full" 0 "$thr" mode=full
if grep -q '700/800 > 60% -> full' "$LAST_DIR/summary.md"; then echo "  PASS  threshold reason in summary"; else echo "  FAIL  threshold reason"; rc=1; fi

# D7 fail-safes: each must be FULL.
case_res "selector exit 64 -> full"            64 "$kyiv" mode=full run_all=true kyiv_count=0
case_res "selector exit 70 -> full"            70 "$sel"  mode=full run_all=true
case_res "selector exit 1 -> full"             1  "$sel"  mode=full run_all=true
case_res "selector exit code garbage -> full"  x  "$sel"  mode=full
case_res "selection.json missing -> full"      0  -       mode=full run_all=true kyiv_count=0
case_res "selection.json empty -> full"        0  ""      mode=full
case_res "selection.json not JSON -> full"     0  "{nope" mode=full
case_res "JSON array, not object -> full"      0  "[]"    mode=full
case_res "unknown mode -> full"                0  '{"mode":"partial","unit":[],"golden":[],"tz_sweep":["test/features/booking/presentation/bookings_day_rail_test.dart"],"integration":[]}' mode=full kyiv_count=0
case_res "missing list key -> full"            0  '{"mode":"selective","unit":["test/a_test.dart"],"golden":[],"tz_sweep":[]}' mode=full
case_res "non-string entry -> full"            0  '{"mode":"selective","unit":[1],"golden":[],"tz_sweep":[],"integration":[]}' mode=full
case_res "option-looking path -> full"         0  '{"mode":"selective","unit":["--coverage"],"golden":[],"tz_sweep":[],"integration":[]}' mode=full
case_res "path traversal -> full"              0  '{"mode":"selective","unit":["test/../x_test.dart"],"golden":[],"tz_sweep":[],"integration":[]}' mode=full
case_res "non-test path -> full"               0  '{"mode":"selective","unit":["lib/main.dart"],"golden":[],"tz_sweep":[],"integration":[]}' mode=full
case_res "none with paths -> full"             0  '{"mode":"none","unit":["test/a_test.dart"],"golden":[],"tz_sweep":[],"integration":[]}' mode=full
case_res "selective with nothing -> full"      0  '{"mode":"selective","unit":[],"golden":[],"tz_sweep":[],"integration":[]}' mode=full
case_res "none with a seed reason -> full"     0  '{"mode":"none","unit":[],"golden":[],"tz_sweep":[],"integration":[],"reasons":[{"path":"lib/a.dart","rule":"seed"}]}' mode=full
case_res "none with a full: reason -> full"    0  '{"mode":"none","unit":[],"golden":[],"tz_sweep":[],"integration":[],"reasons":[{"path":"docs/x.md","rule":"none: docs/**"},{"path":"*","rule":"full: 1 non-docs change(s) selected no tests"}]}' mode=full
case_res "none with a non-string rule -> full" 0  '{"mode":"none","unit":[],"golden":[],"tz_sweep":[],"integration":[],"reasons":[{"path":"x","rule":7}]}' mode=full

# P4: a selective unit list above the threshold warns (stdout + summary) but
# keeps the verdict; at or below it, no warning.
big="$(jq -nc '{mode:"selective",unit:[range(81) | "test/u\(.)_test.dart"],golden:[],tz_sweep:[],integration:[],reasons:[]}')"
case_res "81 unit files -> still selective"    0  "$big"  mode=selective unit_count=81
if grep -q '::warning::selective unit list has 81 files (> 80)' <<<"$(env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY bash "$res" 0 "$LAST_DIR/selection.json")" &&
   grep -q 'Warning:.*81 files (> 80)' "$LAST_DIR/summary.md"; then
  echo "  PASS  > 80 unit files warns (stdout + summary)"
else
  echo "  FAIL  > 80 unit files did not warn"; rc=1
fi
edge="$(jq -nc '{mode:"selective",unit:[range(80) | "test/u\(.)_test.dart"],golden:[],tz_sweep:[],integration:[],reasons:[]}')"
case_res "80 unit files -> selective"          0  "$edge" mode=selective unit_count=80
if grep -q 'Warning' "$LAST_DIR/summary.md"; then echo "  FAIL  80 unit files warned"; rc=1; else echo "  PASS  80 unit files: no warning"; fi

ln -s "$tmp/stale/selection.json" "$tmp/link.json"
out="$(env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY bash "$res" 0 "$tmp/link.json")"
if grep -qx mode=full <<<"$out"; then echo "  PASS  symlinked selection.json -> full"; else echo "  FAIL  symlink accepted"; rc=1; fi

if [ "$rc" -eq 0 ]; then echo "SELF-TEST OK: resolve_selection_test.sh"; fi
exit "$rc"
