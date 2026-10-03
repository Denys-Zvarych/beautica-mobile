#!/usr/bin/env bash
# Phase 076 (10.2) — hermetic test for scripts/perf/measure_jank.sh: the device-free
# `--summarize` table + budget logic, input hardening, and the device path
# driven through a fake `adb` + fake `flutter` on PATH.
#
# Run:   bash scripts/perf/tests/measure-jank.test.sh
#        MEASURE_SCRIPT=/path/to/mutant.sh bash scripts/perf/tests/measure-jank.test.sh   (falsification probes)
# Exit 0 = no FAIL.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${MEASURE_SCRIPT:-$SCRIPT_DIR/../measure_jank.sh}"
[ -f "$TARGET" ] || { echo "FAIL: script under test not found: $TARGET"; exit 2; }
bash -n "$TARGET" || { echo "FAIL: bash -n"; exit 2; }
command -v python3 >/dev/null || { echo "FAIL: python3 required"; exit 2; }

ROOT="$(mktemp -d)"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$ROOT"' EXIT
PASS=0; FAIL=0

check() { # check <label> <expr>
    if eval "$2"; then PASS=$((PASS+1)); echo "  ok     - $1"
    else FAIL=$((FAIL+1)); echo "  FAIL   - $1"; echo "           rc=$RC out: $(printf %s "$OUT" | tail -n 5 | tr '\n' '|')"; fi
}
EXTRA=(HOME="$ROOT/home")
run() { OUT="$(env -u JANK_BUDGET_MS -u ANDROID_SERIAL "${EXTRA[@]}" bash "$TARGET" "$@" 2>&1)"; RC=$?; }
fn() { OUT="$(env "${EXTRA[@]}" bash -c 'source "$1"; set +eu; shift; "$@"' _ "$TARGET" "$@" 2>&1)"; RC=$?; }

# mkjson <file> <my_p90> <my_worst> <search_p90> <search_worst> ... : four surfaces,
# (p90 worst) pairs in my-bookings, search-results, services-list, salon-board order.
# frame_build_times (us) are 5 samples whose lower-middle (3rd of 5 sorted: 1 2 3 8 9 ms) is 3000 us = 3.00 ms.
mkjson() {
  local f="$1"; shift
  python3 - "$f" "$@" <<'PY'
import json, sys
f, vals = sys.argv[1], [float(v) for v in sys.argv[2:]]
names = ["my-bookings", "search-results", "services-list", "salon-board"]
d = {}
for i, n in enumerate(names):
    d[n + "_scroll"] = {
        "average_frame_build_time_millis": 3.5,
        "90th_percentile_frame_build_time_millis": vals[2 * i],
        "worst_frame_build_time_millis": vals[2 * i + 1],
        "frame_count": 120,
        "90th_percentile_frame_rasterizer_time_millis": 2.0,
        "worst_frame_rasterizer_time_millis": 4.0,
        "frame_build_times": [9000, 1000, 2000, 3000, 8000],
    }
json.dump(d, open(f, "w"))
PY
}

echo "[1] within budget -> 0, table + PASS"
mkjson "$ROOT/ok.json" 5 10 6 11 7 12 8 15.99
run --summarize "$ROOT/ok.json"
check "exit 0" '[ $RC -eq 0 ]'
check "PASS line" 'grep -q "^PASS: all 4 surfaces within the 16 ms" <<<"$OUT"'
check "header row" 'grep -Eq "^surface +frames +p50 ms +p90 ms +worst ms +r90 ms +rworst ms +verdict" <<<"$OUT"'
check "my-bookings row: frames 120, p50 3.00, p90 5.00, worst 10.00" 'grep -Eq "^my-bookings +120 +3\.00 +5\.00 +10\.00 +2\.00 +4\.00 +PASS" <<<"$OUT"'
check "salon-board row: worst 15.99 passes" 'grep -Eq "^salon-board +120 +3\.00 +8\.00 +15\.99 +2\.00 +4\.00 +PASS" <<<"$OUT"'
check "rows in the four-surface order" '[ "$(grep -Eo "^(my-bookings|search-results|services-list|salon-board)" <<<"$OUT" | tr "\n" " ")" = "my-bookings search-results services-list salon-board " ]'
run --check "$ROOT/ok.json"; check "--check is an alias" '[ $RC -eq 0 ] && grep -q "^PASS" <<<"$OUT"'

echo "[2] over budget -> 1"
mkjson "$ROOT/p90.json" 5 10 16 11 7 12 8 12
run --summarize "$ROOT/p90.json"
check "p90 == budget fails (strictly-less-than)" '[ $RC -eq 1 ] && grep -Eq "^search-results .*FAIL \(p90 16\.00 >= 16\)" <<<"$OUT"'
check "FAIL budget summary on stderr, no PASS line" 'grep -q "FAIL: frame budget" <<<"$OUT" && ! grep -q "^PASS" <<<"$OUT"'
mkjson "$ROOT/worst.json" 5 10 6 11 7 12 8 40
run --summarize "$ROOT/worst.json"
check "worst over budget fails" '[ $RC -eq 1 ] && grep -Eq "^salon-board .*FAIL \(worst 40\.00 >= 16\)" <<<"$OUT"'
mkjson "$ROOT/both.json" 20 30 6 11 7 12 8 12
run --summarize "$ROOT/both.json"
check "both p90 and worst named in one row" '[ $RC -eq 1 ] && grep -Eq "^my-bookings .*p90 20\.00 >= 16; worst 30\.00 >= 16" <<<"$OUT"'
check "other surfaces still PASS in the same table" 'grep -Eq "^services-list .* PASS" <<<"$OUT"'
EXTRA=(HOME="$ROOT/home" JANK_BUDGET_MS=8)
run --summarize "$ROOT/ok.json"; check "JANK_BUDGET_MS=8 tightens the gate (p90 8 fails)" '[ $RC -eq 1 ]'
EXTRA=(HOME="$ROOT/home" JANK_BUDGET_MS=30)
run --summarize "$ROOT/worst.json"; check "JANK_BUDGET_MS=30 loosens it (worst 40 still fails)" '[ $RC -eq 1 ]'
EXTRA=(HOME="$ROOT/home" JANK_BUDGET_MS=50)
run --summarize "$ROOT/worst.json"; check "JANK_BUDGET_MS=50 passes worst 40" '[ $RC -eq 0 ]'
EXTRA=(HOME="$ROOT/home")

echo "[3] p50 from frame_build_times, with average fallback"
python3 - "$ROOT/even.json" <<'PY'
import json, sys
names = ["my-bookings", "search-results", "services-list", "salon-board"]
base = lambda t: {"90th_percentile_frame_build_time_millis": 5, "worst_frame_build_time_millis": 9,
                  "average_frame_build_time_millis": 7.25, "frame_count": 100, "90th_percentile_frame_rasterizer_time_millis": 1, "worst_frame_rasterizer_time_millis": 2, **({"frame_build_times": t} if t else {})}
d = {n + "_scroll": base([4000, 1000, 3000, 2000]) for n in names}   # sorted 1 2 3 4 ms -> lower-middle 2.00
d["services-list_scroll"] = base(None)                                # no list -> average 7.25, marked ~
json.dump(d, open(sys.argv[1], "w"))
PY
run --summarize "$ROOT/even.json"
check "even list -> lower-middle element (2.00)" 'grep -Eq "^my-bookings +100 +2\.00 " <<<"$OUT"'
check "no list -> average, marked ~" 'grep -Eq "^services-list +100 +7\.25~ " <<<"$OUT"'
check "~ legend printed" 'grep -q "^~ p50 estimated" <<<"$OUT"'
check "still PASS (estimate does not gate)" '[ $RC -eq 0 ]'

echo "[4] bad / missing data is a FAILURE, never skipped"
python3 - "$ROOT/missing.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1].replace("missing", "ok")))
del d["salon-board_scroll"]
json.dump(d, open(sys.argv[1], "w"))
PY
run --summarize "$ROOT/missing.json"
check "missing surface -> 1 and named" '[ $RC -eq 1 ] && grep -q "FAIL: salon-board: surface missing" <<<"$OUT"'
python3 - "$ROOT/nan.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1].replace("nan", "ok")))
d["my-bookings_scroll"]["90th_percentile_frame_build_time_millis"] = "fast"
d["search-results_scroll"]["worst_frame_build_time_millis"] = -1
json.dump(d, open(sys.argv[1], "w"))
PY
run --summarize "$ROOT/nan.json"
check "non-numeric p90 -> 1 and named" '[ $RC -eq 1 ] && grep -q "FAIL: my-bookings: p50/p90/worst/rasterizer p90/worst missing or not a finite number" <<<"$OUT"'
check "negative worst -> 1 and named" 'grep -q "FAIL: search-results: p50/p90/worst/rasterizer" <<<"$OUT"'
printf '{"my-bookings_scroll": {"90th_percentile_frame_build_time_millis": NaN, "worst_frame_build_time_millis": 1}}' >"$ROOT/jnan.json"
run --summarize "$ROOT/jnan.json"; check "NaN literal rejected -> 1" '[ $RC -eq 1 ]'
printf '{not json' >"$ROOT/bad.json"; run --summarize "$ROOT/bad.json"
check "malformed JSON -> 1 with a message" '[ $RC -eq 1 ] && grep -q "cannot parse" <<<"$OUT"'
printf '[1,2]' >"$ROOT/arr.json"; run --summarize "$ROOT/arr.json"; check "array top level -> 1" '[ $RC -eq 1 ] && grep -q "not an object" <<<"$OUT"'
printf '{}' >"$ROOT/empty.json"; run --summarize "$ROOT/empty.json"; check "empty object -> 1 (all four missing)" '[ $RC -eq 1 ] && [ "$(grep -c "surface missing" <<<"$OUT")" -eq 4 ]'
: >"$ROOT/zero.json"; run --summarize "$ROOT/zero.json"; check "zero-byte file -> 1" '[ $RC -eq 1 ] && grep -q "empty or larger" <<<"$OUT"'
run --summarize "$ROOT/absent.json"; check "absent file -> 1" '[ $RC -eq 1 ] && grep -q "not a regular file" <<<"$OUT"'
ln -s "$ROOT/ok.json" "$ROOT/link.json"; run --summarize "$ROOT/link.json"; check "symlinked input refused -> 1" '[ $RC -eq 1 ] && grep -q "not a regular file" <<<"$OUT"'
run --summarize "$ROOT"; check "a directory -> 1" '[ $RC -eq 1 ]'

echo "[5] untrusted names are sanitised in output"
ESC=$(printf '\033')
python3 - "$ROOT/evil.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1].replace("evil", "ok")))
d["evil\x1b[31mX\x1b]0;p\x07_scroll"] = d["my-bookings_scroll"]
json.dump(d, open(sys.argv[1], "w"))
PY
run --summarize "$ROOT/evil.json"
check "no ESC/BEL byte in output" '! grep -q "$ESC" <<<"$OUT" && ! grep -q "$(printf "\a")" <<<"$OUT"'
check "name reduced to its safe characters" 'grep -Eq "^evil31mX0p +120" <<<"$OUT"'
check "an extra surface is shown but never gates" '[ $RC -eq 0 ]'

echo "[6] usage / parse errors"
run --bogus; check "unknown arg -> 64" '[ $RC -eq 64 ]'
run --summarize; check "--summarize without file -> 64" '[ $RC -eq 64 ]'
run --device; check "--device without serial -> 64" '[ $RC -eq 64 ]'
run --summarize "$ROOT/ok.json" --qemu 2; check "bad --qemu -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home" JANK_BUDGET_MS=abc); run --summarize "$ROOT/ok.json"; check "bad budget env -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home" JANK_BUDGET_MS=0); run --summarize "$ROOT/ok.json"; check "zero budget -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home" JANK_DRIVE_TIMEOUT_S=x); run --summarize "$ROOT/ok.json"; check "bad drive timeout -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home" JANK_ADB_TIMEOUT_S=0); run --summarize "$ROOT/ok.json"; check "bad adb timeout -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home")
run; check "no device and no serial -> 64" '[ $RC -eq 64 ] && grep -q "no device" <<<"$OUT"'
run --help; check "--help prints usage, exit 0" '[ $RC -eq 0 ] && grep -q "measure_jank.sh --device" <<<"$OUT"'
check "--help includes env-var section" 'grep -q "^# Env vars (optional):" <<<"$OUT" && grep -q "JANK_REPEATS" <<<"$OUT" && grep -q "JANK_MIN_FRAMES" <<<"$OUT"'
check "--help includes exit codes" 'grep -q "Exit codes:" <<<"$OUT" && grep -q "0 within budget" <<<"$OUT"'
echo "[6b] summarize writes no history and runs no adb"
check "no history dir" '[ ! -e "$ROOT/home/.cache/beautica-history" ]'

echo "[7] serial validation"
for bad in '-x' '--help' 'a b' 'a;rm' '$(id)' 'a/b'; do
  run --device "$bad"; check "rejects serial '$bad' -> 64" '[ $RC -eq 64 ] && grep -q "invalid device serial" <<<"$OUT"'
done
EXTRA=(HOME="$ROOT/home" ANDROID_SERIAL='-bad'); run; check "rejects bad ANDROID_SERIAL env -> 64" '[ $RC -eq 64 ]'; EXTRA=(HOME="$ROOT/home")
for good in 'emulator-5554' '192.168.1.5:5555' 'R5CT1234ABC'; do
  fn valid_serial "$good"; check "accepts serial '$good'" '[ $RC -eq 0 ]'
done

echo "[8] model warnings + sanitising"
run --summarize "$ROOT/ok.json" --model "Pixel 6" --qemu 0; check "physical device: no warning" '[ $RC -eq 0 ] && ! grep -q WARNING <<<"$OUT"'
run --summarize "$ROOT/ok.json" --model "sdk_gphone" --qemu 1; check "emulator warns" 'grep -q "emulator" <<<"$OUT"'
fn sanitize_model "A${ESC}[1mB,c
d"; check "sanitize_model strips ESC/comma/newline" '[ "$OUT" = "A1mBcd" ]'

echo "[9] history: dir/file modes, no overwrite, symlink refusal"
H="$ROOT/hist"; EXTRA=(HOME="$ROOT/home" JANK_HISTORY_DIR="$H")
fn write_history "$ROOT/ok.json" abc1234; check "write ok" '[ $RC -eq 0 ]'
F1="$(ls "$H" | sed -n 1p)"
check "named <date>-<sha>.json" 'grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2}-abc1234\.json$" <<<"$F1"'
check "dir 700 / file 600" '[ "$(stat -c %a "$H")" = 700 ] && [ "$(stat -c %a "$H/$F1")" = 600 ]'
check "content copied verbatim" 'cmp -s "$H/$F1" "$ROOT/ok.json"'
fn write_history "$ROOT/p90.json" abc1234
check "second run does not overwrite (-2 suffix)" '[ "$(ls "$H" | wc -l)" -eq 2 ] && ls "$H" | grep -Eq -- "-abc1234-2\.json$" && cmp -s "$H/$F1" "$ROOT/ok.json"'
fn write_history "$ROOT/p90.json" 'ab c,12
3'; check "sha sanitised in the filename" 'ls "$H" | grep -Eq -- "-abc123\.json$"'
mkdir -p "$ROOT/target"; ln -s "$ROOT/target" "$ROOT/linkdir"; EXTRA=(HOME="$ROOT/home" JANK_HISTORY_DIR="$ROOT/linkdir")
fn write_history "$ROOT/ok.json" sha; check "symlinked dir: warns, rc 0, wrote nothing" '[ $RC -eq 0 ] && grep -q "symlink" <<<"$OUT" && [ -z "$(ls -A "$ROOT/target")" ]'
mkdir -p "$ROOT/h2"; : >"$ROOT/victim"
D="$(date +%F)-sha"; ln -s "$ROOT/victim" "$ROOT/h2/$D.json"; EXTRA=(HOME="$ROOT/home" JANK_HISTORY_DIR="$ROOT/h2")
fn write_history "$ROOT/ok.json" sha; check "symlinked target name: not followed, victim untouched, next name used" '[ $RC -eq 0 ] && [ ! -s "$ROOT/victim" ] && [ -f "$ROOT/h2/$D-2.json" ]'
EXTRA=(HOME="$ROOT/home")

echo "[10] device path with fake adb + fake flutter"
mkdir -p "$ROOT/bin" "$ROOT/mobile/build"
cat >"$ROOT/bin/adb" <<'A'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_LOG"
case "$*" in
  *"get-state"*)               printf '%s\r\n' "${FAKE_STATE:-device}"; exit 0 ;;
  *"dumpsys display"*)         printf '%s' "${FAKE_DUMPSYS-DisplayDeviceInfo{renderFrameRate=60.0, supportedModes [fps=60.0]}}"; exit 0 ;;
  *"getprop"*) [ -n "${FAKE_GETPROP_RC:-}" ] && exit "$FAKE_GETPROP_RC" ;;&
  *"getprop ro.product.model"*) [ -n "${FAKE_GETPROP_HANG:-}" ] && exec sleep 120
                               printf 'Pixel \033[31m6\033]0;x\a\r\n'; exit 0 ;;
  *"getprop ro.kernel.qemu"*)  printf '0\r\n'; exit 0 ;;
  *"getprop"*)                 printf '\r\n'; exit 0 ;;
esac
exit 0
A
cat >"$ROOT/bin/flutter" <<'F'
#!/usr/bin/env bash
# Fake flutter: logs argv + cwd; writes the canned response like the driver would.
echo "flutter $* [cwd=$PWD]" >>"$FAKE_LOG"
case "${FAKE_FLUTTER:-ok}" in
  hang) sleep 120 ;;
  fail) exit 7 ;;
  nofile) exit 0 ;;
  *) mkdir -p build
     if [ -n "${FAKE_SEQ:-}" ]; then
       n=$(( $(cat "$FAKE_SEQ/n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FAKE_SEQ/n"
       cp "$FAKE_SEQ/r$n.json" build/integration_response_data.json
     else cp "$FAKE_RESPONSE" build/integration_response_data.json; fi ;;
esac
exit 0
F
chmod +x "$ROOT/bin/adb" "$ROOT/bin/flutter"
export FAKE_LOG="$ROOT/dev.log" FAKE_RESPONSE="$ROOT/ok.json"
base_env() { EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_RESPONSE="$FAKE_RESPONSE" JANK_MOBILE_DIR="$ROOT/mobile" JANK_HISTORY_DIR="$ROOT/devhist" JANK_REPEATS=1 "$@"); }
rm -rf "$ROOT/devhist"; : >"$FAKE_LOG"; base_env
run --device emulator-5554
check "device run within budget -> 0" '[ $RC -eq 0 ] && grep -q "^PASS" <<<"$OUT"'
check "flutter drive invoked from the mobile dir, profile, driver+target+serial" 'grep -q "^flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/perf/scroll_jank_test.dart --dart-define=JANK_ENFORCE=false -d emulator-5554 \[cwd=$ROOT/mobile\]$" "$FAKE_LOG"'
check "history file written and 600" '[ "$(ls "$ROOT/devhist" | wc -l)" -eq 1 ] && [ "$(stat -c %a "$ROOT/devhist/$(ls "$ROOT/devhist" | sed -n 1p)")" = 600 ]'
check "model sanitised in the banner (no ESC byte)" '! grep -q "$ESC" <<<"$OUT" && grep -q "model: Pixel 31m60x" <<<"$OUT"'
check "table printed" 'grep -Eq "^my-bookings " <<<"$OUT"'
rm -rf "$ROOT/devhist"; : >"$FAKE_LOG"; run --device emulator-5554 --enforce
check "--enforce flips the dart-define" 'grep -q -- "--dart-define=JANK_ENFORCE=true" "$FAKE_LOG"'
check "a STALE response from an earlier run is removed before driving" 'rm -rf "$ROOT/devhist"; cp "$ROOT/ok.json" "$ROOT/mobile/build/integration_response_data.json"; : >"$FAKE_LOG"; base_env FAKE_FLUTTER=nofile; run --device emulator-5554; [ $RC -eq 1 ] && grep -q "wrote no" <<<"$OUT" && [ ! -e "$ROOT/devhist" ]'
echo "[10b] over-budget baseline: JSON still archived, exit 1"
rm -rf "$ROOT/devhist"; : >"$FAKE_LOG"; base_env FAKE_RESPONSE="$ROOT/worst.json"; run --device emulator-5554
check "over budget -> 1" '[ $RC -eq 1 ] && grep -Eq "^salon-board .*FAIL" <<<"$OUT"'
check "baseline JSON archived anyway" '[ "$(ls "$ROOT/devhist" | wc -l)" -eq 1 ]'
echo "[10c] flutter drive failure / timeout"
rm -rf "$ROOT/devhist"; base_env FAKE_FLUTTER=fail; run --device emulator-5554
check "drive failure -> 1, nothing archived" '[ $RC -eq 1 ] && grep -q "flutter drive failed (exit 7)" <<<"$OUT" && [ ! -e "$ROOT/devhist" ]'
base_env FAKE_FLUTTER=hang JANK_DRIVE_TIMEOUT_S=1; SECONDS=0; run --device emulator-5554; DUR=$SECONDS
check "hung drive killed by the timeout" '[ $RC -eq 1 ] && grep -q "flutter drive timed out after 1s" <<<"$OUT" && [ "$DUR" -lt 60 ]'
echo "[10d] hung getprop is killed and reported"
: >"$FAKE_LOG"; base_env FAKE_GETPROP_HANG=1 JANK_ADB_TIMEOUT_S=1; SECONDS=0; run --device emulator-5554; DUR=$SECONDS
check "getprop timeout -> 1 with ERROR" '[ $RC -eq 1 ] && grep -q "^ERROR: adb getprop ro.product.model timed out after 1s" <<<"$OUT"'
check "fires promptly (<10s) and flutter never ran" '[ "$DUR" -lt 10 ] && ! grep -q "^flutter" "$FAKE_LOG"'
echo "[10e] missing mobile dir"
base_env JANK_MOBILE_DIR="$ROOT/nope"; run --device emulator-5554
check "missing mobile dir -> 1" '[ $RC -eq 1 ] && grep -q "mobile dir not found" <<<"$OUT"'
EXTRA=(HOME="$ROOT/home")

echo "[11] N4 raster gate + table columns"
mkjson "$ROOT/r.json" 5 10 6 11 7 12 8 12
python3 - "$ROOT/r.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["my-bookings_scroll"]["90th_percentile_frame_rasterizer_time_millis"] = 17.5
d["salon-board_scroll"]["worst_frame_rasterizer_time_millis"] = 33
json.dump(d, open(sys.argv[1], "w"))
PY
run --summarize "$ROOT/r.json"
check "raster p90 over budget fails and is named" '[ $RC -eq 1 ] && grep -Eq "^my-bookings .*FAIL \(r90 17\.50 >= 16\)" <<<"$OUT"'
check "raster worst over budget fails and is named" 'grep -Eq "^salon-board .*FAIL \(rworst 33\.00 >= 16\)" <<<"$OUT"'
python3 - "$ROOT/rmiss.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1].replace("rmiss", "ok")))
del d["services-list_scroll"]["worst_frame_rasterizer_time_millis"]
json.dump(d, open(sys.argv[1], "w"))
PY
run --summarize "$ROOT/rmiss.json"
check "missing raster figure is a failure" '[ $RC -eq 1 ] && grep -q "FAIL: services-list: p50/p90/worst/rasterizer" <<<"$OUT"'

echo "[12] N5 frame_count floor"
python3 - "$ROOT/few.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1].replace("few", "ok")))
d["search-results_scroll"]["frame_count"] = 59
json.dump(d, open(sys.argv[1], "w"))
PY
run --summarize "$ROOT/few.json"
check "59 frames < default floor 60 -> 1 with 'too few frames'" '[ $RC -eq 1 ] && grep -Eq "^search-results .*FAIL \(too few frames \(59 < 60\)\)" <<<"$OUT"'
EXTRA=(HOME="$ROOT/home" JANK_MIN_FRAMES=59); run --summarize "$ROOT/few.json"; check "JANK_MIN_FRAMES=59 admits 59 frames" '[ $RC -eq 0 ]'
EXTRA=(HOME="$ROOT/home" JANK_MIN_FRAMES=x); run --summarize "$ROOT/few.json"; check "bad JANK_MIN_FRAMES -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home" JANK_REPEATS=0); run --summarize "$ROOT/few.json"; check "bad JANK_REPEATS -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home")
run --summarize "$ROOT/ok.json" --hz 90; check "--hz 90 -> 11.11 budget (worst 15.99 fails)" '[ $RC -eq 1 ] && grep -q "11.11 ms" <<<"$OUT"'

echo "[13] N6 refresh-rate budget + repeats/median (fake adb + flutter)"
rm -rf "$ROOT/devhist"; base_env FAKE_DUMPSYS='mActiveMode=Mode{fps=90.000004}'; run --device emulator-5554
check "90 Hz display -> budget 11.11 shown and ok.json (worst 15.99) fails" '[ $RC -eq 1 ] && grep -q "display 90 Hz -> frame budget 11.11 ms" <<<"$OUT" && grep -Eq "^salon-board .*FAIL" <<<"$OUT"'
rm -rf "$ROOT/devhist"; base_env FAKE_DUMPSYS='garbage'; run --device emulator-5554
check "unreadable refresh rate -> 60 Hz + warning" '[ $RC -eq 0 ] && grep -q "WARNING: could not read the device refresh rate" <<<"$OUT" && grep -q "display 60 Hz" <<<"$OUT"'
rm -rf "$ROOT/devhist"; base_env FAKE_DUMPSYS=$'x\033[31m renderFrameRate=120.0\a'; run --device emulator-5554
check "refresh rate output is scrubbed (120 Hz parsed, no ESC)" 'grep -q "display 120 Hz" <<<"$OUT" && ! grep -q "$ESC" <<<"$OUT"'
rm -rf "$ROOT/devhist"; base_env JANK_BUDGET_MS=40 FAKE_DUMPSYS='fps=90.0'; run --device emulator-5554
check "JANK_BUDGET_MS overrides the derived budget" '[ $RC -eq 0 ] && ! grep -q "frame budget 11.11" <<<"$OUT"'
SEQ="$ROOT/seq"; rm -rf "$SEQ"; mkdir -p "$SEQ"
mkjson "$SEQ/r1.json" 5 10 6 11 7 12 8 10
mkjson "$SEQ/r2.json" 5 10 6 11 7 12 8 40
mkjson "$SEQ/r3.json" 5 10 6 11 7 12 8 10
rm -rf "$ROOT/devhist"; : >"$FAKE_LOG"; base_env FAKE_SEQ="$SEQ" JANK_REPEATS=3; run --device emulator-5554
check "3 repeats: one outlier (worst 10/40/10) -> median 10 passes" '[ $RC -eq 0 ] && [ "$(grep -c "^flutter drive" "$FAKE_LOG")" -eq 3 ] && grep -q "median of 3 runs" <<<"$OUT"'
check "salon-board row shows the median worst" 'grep -Eq "^salon-board .* 10\.00 .*PASS" <<<"$OUT"'
check "each run archived" '[ "$(ls "$ROOT/devhist" | wc -l)" -eq 3 ]'
mkjson "$SEQ/r1.json" 5 10 6 11 7 12 8 40
rm -f "$SEQ/n"; rm -rf "$ROOT/devhist"; base_env FAKE_SEQ="$SEQ" JANK_REPEATS=3; run --device emulator-5554
check "two bad runs of three (40/40/10) -> median 40 fails" '[ $RC -eq 1 ] && grep -Eq "^salon-board .*FAIL \(worst 40\.00" <<<"$OUT"'
base_env

echo "[14] N7 dirty-tree history suffix"
G="$ROOT/gitmobile"; mkdir -p "$G"; printf 'build/\n' >"$G/.gitignore"; printf 'a\n' >"$G/f.txt"
git -C "$G" init -q && git -C "$G" add -A && git -C "$G" -c user.email=t@t -c user.name=t commit -qm i
rm -rf "$ROOT/devhist"; base_env JANK_MOBILE_DIR="$G"; run --device emulator-5554
check "clean tree: <date>-<sha>.json with no -dirty" '[ $RC -eq 0 ] && ! ls "$ROOT/devhist" | grep -q dirty'
printf 'b\n' >>"$G/f.txt"; rm -rf "$ROOT/devhist"; run --device emulator-5554
D1="$(ls "$ROOT/devhist" | sed -n 1p)"
check "dirty tree: name has -dirty-<7 hex>" 'grep -Eq -- "-[0-9a-f]{7,}-dirty-[0-9a-f]{7}\.json$" <<<"$D1"'
printf 'c\n' >>"$G/f.txt"; rm -rf "$ROOT/devhist"; run --device emulator-5554
D2="$(ls "$ROOT/devhist" | sed -n 1p)"
check "a different diff gives a different hash" '[ "$D1" != "$D2" ] && grep -q dirty <<<"$D2"'
EXTRA=(HOME="$ROOT/home")

echo "[15] L2 history: no temp leftovers, no overwrite of a pre-planted name"
H3="$ROOT/h3"; EXTRA=(HOME="$ROOT/home" JANK_HISTORY_DIR="$H3")
fn write_history "$ROOT/ok.json" sha; fn write_history "$ROOT/ok.json" sha
check "two writes -> two files, no .tmp leftovers" '[ "$(ls -A "$H3" | wc -l)" -eq 2 ] && ! ls -A "$H3" | grep -q "^\.tmp"'
ln -s "$ROOT/victim" "$H3/$(date +%F)-planted.json" 2>/dev/null; : >"$ROOT/victim"
fn write_history "$ROOT/ok.json" planted
check "a pre-planted symlink at the target name is never followed" '[ ! -s "$ROOT/victim" ] && [ -f "$H3/$(date +%F)-planted-2.json" ]'

echo "[16] L3 symlinked ancestor under HOME refused"
mkdir -p "$ROOT/home/real"; ln -s "$ROOT/home/real" "$ROOT/home/lnk"
EXTRA=(HOME="$ROOT/home" JANK_HISTORY_DIR="$ROOT/home/lnk/sub/hist")
fn write_history "$ROOT/ok.json" sha
check "warns, rc 0, wrote nothing through the link" '[ $RC -eq 0 ] && grep -q "symlink" <<<"$OUT" && [ -z "$(ls -A "$ROOT/home/real")" ]'
EXTRA=(HOME="$ROOT/home" JANK_HISTORY_DIR="$ROOT/home/ok/sub/hist")
fn write_history "$ROOT/ok.json" sha
check "plain nested dir under HOME still works" '[ $RC -eq 0 ] && [ "$(ls "$ROOT/home/ok/sub/hist" | wc -l)" -eq 1 ]'

echo "[17] L4 preflight + getprop rc 127"
: >"$FAKE_LOG"; base_env FAKE_STATE=offline; run --device emulator-5554
check "offline -> 1 with clear message, no getprop/flutter" '[ $RC -eq 1 ] && grep -q "is not attached (adb get-state: .offline.)" <<<"$OUT" && ! grep -Eq "getprop|^flutter" "$FAKE_LOG"'
base_env FAKE_GETPROP_RC=127; run --device emulator-5554
check "getprop rc 127 -> 1 with ERROR" '[ $RC -eq 1 ] && grep -q "^ERROR: adb getprop ro.product.model failed (exit 127" <<<"$OUT"'
FARM="$ROOT/farm"; mkdir -p "$FARM"
for t in /usr/bin/*; do n="${t##*/}"; case "$n" in adb|flutter|timeout) ;; *) ln -sf "$t" "$FARM/$n" ;; esac; done
for missing in adb flutter timeout; do
  mkdir -p "$ROOT/fp-$missing"; cp "$ROOT/bin/adb" "$ROOT/bin/flutter" "$ROOT/fp-$missing/"; ln -sf /usr/bin/timeout "$ROOT/fp-$missing/timeout"
  rm -f "$ROOT/fp-$missing/$missing"
  base_env PATH="$ROOT/fp-$missing:$FARM"; run --device emulator-5554
  check "missing $missing -> 1 naming the tool" '[ $RC -eq 1 ] && grep -q "required tool not found on PATH: '"$missing"'" <<<"$OUT"'
done
EXTRA=(HOME="$ROOT/home")

echo "[18] L5 user-supplied path scrubbed"
BADF="$ROOT/ev${ESC}[31mil${ESC}]0;x"
run --summarize "$BADF"
check "absent file with ESC in name: no ESC byte, still fails" '[ $RC -eq 1 ] && ! grep -q "$ESC" <<<"$OUT" && grep -q "not a regular file" <<<"$OUT"'
printf '{not json' >"$BADF"; run --summarize "$BADF"
check "unparsable file with ESC in name: no ESC byte" '[ $RC -eq 1 ] && ! grep -q "$ESC" <<<"$OUT" && grep -q "cannot parse" <<<"$OUT"'
: >"$BADF"; run --summarize "$BADF"
check "empty file with ESC in name: no ESC byte" '[ $RC -eq 1 ] && ! grep -q "$ESC" <<<"$OUT" && grep -q "empty or larger" <<<"$OUT"'

echo "[19] N1 history: ln always fails -> cp fallback / bounded give-up; mktemp failure"
FB="$ROOT/fakeln"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 1\n' >"$FB/ln"; chmod +x "$FB/ln"
H4="$ROOT/h4"; EXTRA=(HOME="$ROOT/home" JANK_HISTORY_DIR="$H4" PATH="$FB:$PATH")
S0=$SECONDS; fn write_history "$ROOT/ok.json" sha; S1=$SECONDS
check "ln fails everywhere: cp -n fallback writes the file, rc 0, 600, no .tmp" '[ $RC -eq 0 ] && [ "$(ls -A "$H4" | wc -l)" -eq 1 ] && ! ls -A "$H4" | grep -q "^\.tmp" && [ "$(stat -c %a "$H4"/*.json)" = 600 ] && cmp -s "$ROOT/ok.json" "$H4"/*.json'
printf '#!/bin/sh\nexit 1\n' >"$FB/cp"; chmod +x "$FB/cp"; rm -rf "$H4"
OUT="$(env "${EXTRA[@]}" JANK_HISTORY_MAX_TRIES=20 timeout --signal=KILL 30 bash -c 'source "$1"; set +eu; shift; "$@"' _ "$TARGET" write_history "$ROOT/ok.json" sha 2>&1)"; RC=$?
check "ln AND cp always fail: gives up after the 20-try cap (not killed by the 30 s guard), rc 0, prints the warning" '[ $RC -eq 0 ] && grep -q "WARNING: gave up after 20 attempts" <<<"$OUT" && ! ls -A "$H4" | grep -q "^\.tmp"'
rm -rf "$FB/ln" "$FB/cp"; printf '#!/bin/sh\nexit 1\n' >"$FB/mktemp"; chmod +x "$FB/mktemp"
fn write_history "$ROOT/ok.json" sha
check "mktemp fails: warns, rc 0, no loop" '[ $RC -eq 0 ] && grep -q "could not create a temp file" <<<"$OUT"'
EXTRA=(HOME="$ROOT/home")

echo "[20] N2 a surface missing from some repeats is a failure"
python3 - "$ROOT/ok.json" "$ROOT/nosalon.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.pop("salon-board_scroll"); json.dump(d, open(sys.argv[2], "w"))
PY
python3 - "$ROOT/ok.json" "$ROOT/extra.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["bonus-surface_scroll"] = d["my-bookings_scroll"]; json.dump(d, open(sys.argv[2], "w"))
PY
run --summarize "$ROOT/ok.json" --summarize "$ROOT/ok.json" --summarize "$ROOT/nosalon.json"
check "salon-board in 2 of 3 runs -> exit 1 naming surface and counts" '[ $RC -eq 1 ] && grep -q "FAIL: surface salon-board missing from 1 of 3 runs" <<<"$OUT" && ! grep -q "^PASS" <<<"$OUT"'
run --summarize "$ROOT/ok.json" --summarize "$ROOT/ok.json" --summarize "$ROOT/extra.json"
check "extra surface in 1 of 3 runs -> exit 1" '[ $RC -eq 1 ] && grep -q "FAIL: surface bonus-surface missing from 2 of 3 runs" <<<"$OUT"'
run --summarize "$ROOT/ok.json" --summarize "$ROOT/ok.json" --summarize "$ROOT/ok.json"
check "all surfaces in every run still passes" '[ $RC -eq 0 ]'

echo "[21] N3 even repeat counts gate the UPPER median"
mkjson "$ROOT/w10.json" 5 10 6 11 7 12 8 10
mkjson "$ROOT/w40.json" 5 10 6 11 7 12 8 40
run --summarize "$ROOT/w10.json" --summarize "$ROOT/w40.json"
check "2 runs (10,40): upper median 40 fails" '[ $RC -eq 1 ] && grep -Eq "^salon-board .*FAIL \(worst 40\.00" <<<"$OUT"'
run --summarize "$ROOT/w10.json" --summarize "$ROOT/w10.json" --summarize "$ROOT/w40.json" --summarize "$ROOT/w40.json"
check "4 runs (10,10,40,40): upper median 40 fails" '[ $RC -eq 1 ] && grep -Eq "^salon-board .*FAIL \(worst 40\.00" <<<"$OUT"'
run --summarize "$ROOT/w10.json" --summarize "$ROOT/w10.json" --summarize "$ROOT/w10.json" --summarize "$ROOT/w40.json"
check "4 runs (10,10,10,40): upper median 10 passes" '[ $RC -eq 0 ]'
run --summarize "$ROOT/w10.json" --summarize "$ROOT/w10.json"
check "2 runs (10,10) pass" '[ $RC -eq 0 ]'

echo "[22] JANK_NO_DDS wiring: default adds nothing, =1 adds --no-dds to flutter drive"
OUT="$(env -u JANK_NO_DDS bash -c 'source "$1"; set +eu; echo "[${DRIVE_EXTRA[*]}]"' _ "$TARGET" 2>&1)"; RC=$?
check "default: DRIVE_EXTRA empty" '[ "$OUT" = "[]" ]'
OUT="$(JANK_NO_DDS=1 bash -c 'source "$1"; set +eu; echo "[${DRIVE_EXTRA[*]}]"' _ "$TARGET" 2>&1)"; RC=$?
check "JANK_NO_DDS=1: --no-dds" '[ "$OUT" = "[--no-dds]" ]'
check "flutter drive invocation consumes DRIVE_EXTRA" 'grep -q "\"\${DRIVE_EXTRA\[@\]}\"" "$TARGET"'

echo
echo "RESULT: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
