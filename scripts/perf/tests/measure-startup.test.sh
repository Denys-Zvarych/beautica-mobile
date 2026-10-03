#!/usr/bin/env bash
# Phase 075 (10.1) — hermetic test for scripts/perf/measure_startup.sh `--check` mode (budget logic, no device).
#
# Run:   ./scripts/perf/tests/measure-startup.test.sh
#        MEASURE_SCRIPT=/path/to/mutant.sh ./scripts/perf/tests/measure-startup.test.sh   (falsification probes)
# Exit 0 = no FAIL.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${MEASURE_SCRIPT:-$SCRIPT_DIR/../measure_startup.sh}"
[ -f "$TARGET" ] || { echo "FAIL: script under test not found: $TARGET"; exit 2; }
bash -n "$TARGET" || { echo "FAIL: bash -n"; exit 2; }

ROOT="$(mktemp -d)"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$ROOT"' EXIT
PASS=0; FAIL=0

check() { # check <label> <expr>
    if eval "$2"; then PASS=$((PASS+1)); echo "  ok     - $1"
    else FAIL=$((FAIL+1)); echo "  FAIL   - $1"; echo "           rc=$RC out: $(printf %s "$OUT" | tail -n 4 | tr '\n' '|')"; fi
}
run() { OUT="$(env -u STARTUP_COLD_BUDGET_MS -u STARTUP_WARM_BUDGET_MS -u STARTUP_COLD_BUDGET_US -u ANDROID_SERIAL "${EXTRA[@]}" bash "$TARGET" "$@" 2>&1)"; RC=$?; }
# fn <function> [args] : source the script (main is guarded) and call one function.
fn() { OUT="$(env "${EXTRA[@]}" bash -c 'source "$1"; set +eu; shift; "$@"' _ "$TARGET" "$@" 2>&1)"; RC=$?; }
EXTRA=(HOME="$ROOT/home")

cat >"$ROOT/start_up_info.json" <<'J'
{
  "engineEnterTimestampMicros": 1,
  "timeToFirstFrameMicros": 1500000,
  "timeToFirstFrameRasterizedMicros": 9999999
}
J
# Fixture trace: async b/e (what StartupTrace emits), one slice over 100 ms, a legacy B/E pair,
# noise events, an unmatched b (must be ignored), and non-boot names.
cat >"$ROOT/timeline.json" <<'J'
{"traceEvents": [
 {"name": "Engine::Init", "ph": "X", "ts": 10, "dur": 999999},
 {"name": "boot:timezones", "ph": "b", "id": "1", "ts": 1000},
 {"name": "boot:timezones", "ph": "e", "id": "1", "ts": 21000},
 {"name": "boot:fonts", "ph": "b", "id": "2", "ts": 30000},
 {"name": "boot:certPinning", "ph": "b", "id": "3", "ts": 31000},
 {"name": "boot:certPinning", "ph": "e", "id": "3", "ts": 36000},
 {"name": "boot:fonts", "ph": "e", "id": "2", "ts": 250000},
 {"name": "boot:container", "ph": "B", "ts": 300000},
 {"name": "boot:container", "ph": "E", "ts": 340000},
 {"name": "boot:dangling", "ph": "b", "id": "9", "ts": 400000},
 {"name": "other:fonts", "ph": "b", "id": "2", "ts": 1},
 {"name": "other:fonts", "ph": "e", "id": "2", "ts": 999999}
]}
J

echo "[1] under budget (cold 1500, warm 500) -> 0";  run --check 1500 500
check "exit 0" '[ $RC -eq 0 ]'; check "PASS line" 'grep -q "^PASS" <<<"$OUT"'
echo "[2] exactly at budget (cold 2000, warm 800) -> 0"; run --check 2000 800
check "exit 0" '[ $RC -eq 0 ]'
echo "[3] cold over budget -> 1"; run --check 2500 500
check "exit 1" '[ $RC -eq 1 ]'; check "FAIL cold line" 'grep -q "FAIL: cold start over budget by 500 ms" <<<"$OUT"'
echo "[4] warm over budget -> 1"; run --check 1500 801
check "exit 1" '[ $RC -eq 1 ]'; check "FAIL warm line" 'grep -q "FAIL: warm start over budget by 1 ms" <<<"$OUT"'
echo "[5] env budgets override"; EXTRA=(HOME="$ROOT/home" STARTUP_COLD_BUDGET_MS=1000); run --check 1500 500
check "exit 1 with tighter cold budget" '[ $RC -eq 1 ]'; EXTRA=(HOME="$ROOT/home")
EXTRA=(HOME="$ROOT/home" STARTUP_COLD_BUDGET_US=1); run --check 1500 500
check "retired _US var warns and is ignored" '[ $RC -eq 0 ] && grep -q "retired" <<<"$OUT"'; EXTRA=(HOME="$ROOT/home")
echo "[6] usage / parse errors"
EXTRA=(HOME="$ROOT/home" STARTUP_WARM_BUDGET_MS=abc); run --check 1 1; check "bad budget -> 64" '[ $RC -eq 64 ]'; EXTRA=(HOME="$ROOT/home")
run --bogus; check "unknown arg -> 64" '[ $RC -eq 64 ]'
run --check 1500 abc; check "non-integer warm -> 64" '[ $RC -eq 64 ]'
run --check 1,x 1; check "bad sample list -> 64" '[ $RC -eq 64 ]'
run --check 1500 500 --info "$ROOT/missing.json"; check "missing info file -> 1" '[ $RC -eq 1 ]'
printf '{"timeToFirstFrameRasterizedMicros": 1}\n' >"$ROOT/nokey.json"
run --check 1500 500 --info "$ROOT/nokey.json"; check "missing key (Rasterized must not match) -> 1" '[ $RC -eq 1 ]'
run; check "no device and no serial -> 64" '[ $RC -eq 64 ]'
echo "[7] check mode writes no history"; check "no history file" '[ ! -e "$ROOT/home/.cache/beautica-history/startup-history-v2.csv" ]'

echo "[8] median over 5 samples"
run --check 3000,1800,1900,2100,1700 500   # sorted 1700 1800 1900 2100 3000 -> 1900
check "median 1900 passes a 2000 budget (outlier ignored)" '[ $RC -eq 0 ] && grep -q "median: 1900 ms" <<<"$OUT"'
run --check 2100,2200,2300,100,100 500       # sorted 100 100 2100 2200 2300 -> 2100
check "median 2100 fails the 2000 budget (low outliers ignored)" '[ $RC -eq 1 ] && grep -q "over budget by 100 ms" <<<"$OUT"'
run --check 1500 100,900,900,900,100         # warm sorted 100 100 900 900 900 -> 900
check "warm median 900 fails the 800 budget" '[ $RC -eq 1 ] && grep -q "warm start over budget by 100 ms" <<<"$OUT"'
fn median 5 1 4 2 3; check "median fn odd list" '[ "$OUT" = 3 ]'
fn median 4 1 3 2;   check "median fn even list = lower-middle" '[ "$OUT" = 2 ]'

echo "[9] serial validation"
for bad in '-x' '--help' 'a b' 'a;rm' '$(id)' 'a/b'; do
  run --device "$bad"; check "rejects serial '$bad' -> 64" '[ $RC -eq 64 ] && grep -q "invalid device serial" <<<"$OUT"'
done
EXTRA=(HOME="$ROOT/home" ANDROID_SERIAL='-bad'); run; check "rejects bad ANDROID_SERIAL env -> 64" '[ $RC -eq 64 ]'; EXTRA=(HOME="$ROOT/home")
for good in 'emulator-5554' '192.168.1.5:5555' 'R5CT1234ABC'; do
  fn valid_serial "$good"; check "accepts serial '$good'" '[ $RC -eq 0 ]'
done

echo "[10] boot:* slice parsing from a fixture trace"
run --check 1500 500 --timeline "$ROOT/timeline.json"
check "exit 0 (slices are attribution, not a gate)" '[ $RC -eq 0 ]'
check "timezones 20000 us" 'grep -Eq "boot:timezones +20000 us( |$)" <<<"$OUT" && ! grep -E "boot:timezones" <<<"$OUT" | grep -q OVER'
check "fonts 220000 us flagged OVER 100 ms" 'grep -E "boot:fonts +220000 us +OVER 100 ms" <<<"$OUT" >/dev/null'
check "certPinning (nested, interleaved) 5000 us" 'grep -Eq "boot:certPinning +5000 us" <<<"$OUT"'
check "legacy B/E container 40000 us" 'grep -Eq "boot:container +40000 us" <<<"$OUT"'
check "unmatched b ignored" '! grep -q dangling <<<"$OUT"'
check "non-boot events ignored" '! grep -q "other:fonts" <<<"$OUT"'
check "only the one slice is flagged" '[ "$(grep -c OVER <<<"$OUT")" -eq 1 ]'
run --check 1500 500 --timeline "$ROOT/none.json"; check "missing timeline warns, no failure" '[ $RC -eq 0 ] && grep -q "WARNING.*not found" <<<"$OUT"'
check "missing timeline prints loud UNAVAILABLE line" 'grep -q "boot:\* slices UNAVAILABLE (no start_up_timeline.json)" <<<"$OUT"'
check "missing timeline still evaluates budget" 'grep -q "^PASS" <<<"$OUT"'
printf '{"traceEvents": []}' >"$ROOT/empty.json"
run --check 1500 500 --timeline "$ROOT/empty.json"; check "no boot slices warns" '[ $RC -eq 0 ] && grep -q "no boot:\* slices" <<<"$OUT"'
run --check 1500 500 --info "$ROOT/start_up_info.json"
check "info is labelled attribution/engine-init" 'grep -q "attribution only (starts at engine init): timeToFirstFrameMicros 1500000" <<<"$OUT"'

echo "[11] device model warnings"
run --check 1500 500 --model "Pixel 6" --qemu 0; check "reference device: no warning" '[ $RC -eq 0 ] && ! grep -q WARNING <<<"$OUT"'
run --check 1500 500 --model "Galaxy A14" --qemu 0; check "other model warns" 'grep -q "not the reference" <<<"$OUT"'
run --check 1500 500 --model "Pixel 6" --qemu 1; check "emulator warns" 'grep -q "emulator" <<<"$OUT"'
ESC=$(printf '\033')
run --check 1500 500 --model "Evil${ESC}[31mPhone${ESC}]0;x" --qemu 0
check "model sanitized before warning (no ESC byte)" '! grep -q "$ESC" <<<"$OUT" && grep -q "Evil31mPhone0x" <<<"$OUT"'
fn sanitize_model "A${ESC}[1mB,c
d"; check "sanitize_model strips ESC/comma/newline" '[ "$OUT" = "A1mBcd" ]'

echo "[12] history: model column + symlink refusal"
H="$ROOT/hist"; EXTRA=(HOME="$ROOT/home" STARTUP_HISTORY_DIR="$H")
fn write_history 1900 700 'Pixel 6,evil
x'; check "write ok" '[ $RC -eq 0 ]'
check "header has model column" '[ "$(sed -n 1p "$H/startup-history-v2.csv")" = "date,sha,model,cold_ms,warm_ms" ]'
check "row has sanitized model, cold, warm" 'sed -n 2p "$H/startup-history-v2.csv" | grep -Eq "^[0-9-]+,[^,]+,Pixel 6evilx,1900,700$"'
check "dir 700 / file 600" '[ "$(stat -c %a "$H")" = 700 ] && [ "$(stat -c %a "$H/startup-history-v2.csv")" = 600 ]'
mkdir -p "$ROOT/target"; ln -s "$ROOT/target" "$ROOT/linkdir"; EXTRA=(HOME="$ROOT/home" STARTUP_HISTORY_DIR="$ROOT/linkdir")
fn write_history 1 1 m; check "symlinked dir: warns, rc 0, wrote nothing" '[ $RC -eq 0 ] && grep -q "symlink" <<<"$OUT" && [ -z "$(ls -A "$ROOT/target")" ]'
mkdir -p "$ROOT/h2"; : >"$ROOT/victim"; ln -s "$ROOT/victim" "$ROOT/h2/startup-history-v2.csv"; EXTRA=(HOME="$ROOT/home" STARTUP_HISTORY_DIR="$ROOT/h2")
fn write_history 1 1 m; check "symlinked file: warns, rc 0, victim untouched" '[ $RC -eq 0 ] && grep -q "symlink" <<<"$OUT" && [ ! -s "$ROOT/victim" ]'
EXTRA=(HOME="$ROOT/home")

echo "[13] launch_ms / series with a fake adb on PATH"
mkdir -p "$ROOT/bin"
cat >"$ROOT/bin/adb" <<'A'
#!/usr/bin/env bash
# Fake adb: logs argv; `am start -W` pops canned TotalTimes from $FAKE_TIMES (one per line).
echo "$*" >>"$FAKE_LOG"
case "$*" in
  *"get-state"*) printf '%s\r\n' "${FAKE_STATE:-device}"; exit 0 ;;
  *"getprop"*) [ -n "${FAKE_GETPROP_HANG:-}" ] && exec sleep 120; [ -n "${FAKE_GETPROP_RC:-}" ] && exit "$FAKE_GETPROP_RC" ;;
  *"pidof"*) if [ -s "${FAKE_PIDOF_FAILS:-/nonexistent}" ] && [ "$(cat "$FAKE_PIDOF_FAILS")" -gt 0 ]; then n=$(cat "$FAKE_PIDOF_FAILS"); echo $((n-1)) >"$FAKE_PIDOF_FAILS"; exit 1; fi
             printf '1234\r\n'; exit 0 ;;
  *"am force-stop"*) [ -n "${FAKE_STOP_HANG:-}" ] && exec sleep 120 ;;
  *"am start -W"*)
    case "${FAKE_MODE:-ok}" in
      hang) sleep 120 ;;
      esc) printf 'Error: \033[31mevil\033]0;x\a\r\n' ;;
      fail) printf 'Starting: Intent\r\nError type 3\r\nError: Activity class does not exist.\r\n' ;;
      *) n=$(head -n1 "$FAKE_TIMES"); sed -i 1d "$FAKE_TIMES"
         printf 'Starting: Intent { cmp=x }\r\nStatus: ok\r\nTotalTime: %s\r\nWaitTime: 9\r\n' "$n" ;;
    esac ;;
esac
exit 0
A
printf '#!/usr/bin/env bash\nexit 0\n' >"$ROOT/bin/flutter"
chmod +x "$ROOT/bin/adb" "$ROOT/bin/flutter"
export FAKE_LOG="$ROOT/adb.log" FAKE_TIMES="$ROOT/times"
EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES")
# series prints samples then the median on a final line.
printf '%s\n' 1900 1700 3000 1800 2100 >"$FAKE_TIMES"; : >"$FAKE_LOG"
fn_series() { OUT="$(env "${EXTRA[@]}" bash -c 'source "$1"; set +eu; shift; series "$@"; echo "MEDIAN=$SERIES_MEDIAN"' _ "$TARGET" "$@" 2>&1)"; RC=$?; }
fn_series dev-1 0 Cold
check "series rc 0" '[ $RC -eq 0 ]'
check "5 samples taken" '[ "$(grep -c "am start -W" "$FAKE_LOG")" -eq 5 ]'
check "5 force-stops of the package" '[ "$(grep -c "^-s dev-1 shell am force-stop com.beautica.beautica_mobile$" "$FAKE_LOG")" -eq 5 ]'
check "every launch is immediately preceded by a force-stop" '[ "$(grep -B1 "am start -W" "$FAKE_LOG" | grep -c "am force-stop com.beautica.beautica_mobile")" -eq 5 ]'
check "log strictly alternates force-stop / start" '[ "$(awk "NR%2==1 && /force-stop/ {a++} NR%2==0 && /start -W/ {b++} END{print a+b}" "$FAKE_LOG")" -eq 10 ]'
check "samples line lists all 5 (CR stripped)" 'grep -q "samples: 1900 1700 3000 1800 2100" <<<"$OUT"'
check "median 1900" 'grep -q "^MEDIAN=1900$" <<<"$OUT"'
echo "[13b] failed launch prints raw output and exits 1"
: >"$FAKE_LOG"; EXTRA+=(FAKE_MODE=fail); fn_series dev-1 0 Cold
check "failed launch exits 1" '[ $RC -eq 1 ]'
check "raw am output shown" 'grep -q "Activity class does not exist" <<<"$OUT" && grep -q "launch failed" <<<"$OUT"'
check "stopped after first failure (1 launch)" '[ "$(grep -c "am start -W" "$FAKE_LOG")" -eq 1 ]'
check "no MEDIAN printed on failure" '! grep -q "^MEDIAN=" <<<"$OUT"'
echo "[13b2] raw am output is scrubbed of ESC/control bytes"
: >"$FAKE_LOG"; EXTRA+=(FAKE_MODE=esc); fn_series dev-1 0 Cold
check "raw output shown but no ESC/BEL byte" 'grep -q "evil" <<<"$OUT" && ! grep -q "$ESC" <<<"$OUT" && ! grep -q "$(printf "\a")" <<<"$OUT"'
echo "[13c] hung am start -W is killed by the timeout"
: >"$FAKE_LOG"; EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES" FAKE_MODE=hang STARTUP_LAUNCH_TIMEOUT_S=1)
SECONDS=0; fn_series dev-1 0 Cold; DUR=$SECONDS
check "timeout -> exit 1 with clear message" '[ $RC -eq 1 ] && grep -q "timed out after 1s" <<<"$OUT"'
check "timeout fires promptly (<60s, not the 120s hang)" '[ "$DUR" -lt 60 ]'
echo "[13d] hung force-stop is killed by the timeout"
: >"$FAKE_LOG"; EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES" FAKE_STOP_HANG=1 STARTUP_LAUNCH_TIMEOUT_S=1)
SECONDS=0; fn_series dev-1 0 Cold; DUR=$SECONDS
check "force-stop timeout -> exit 1 with clear message" '[ $RC -eq 1 ] && grep -q "force-stop.*timed out after 1s" <<<"$OUT"'
check "force-stop timeout fires promptly (<60s, not the 120s hang)" '[ "$DUR" -lt 60 ]'
check "no launch attempted after hung force-stop" '! grep -q "am start -W" "$FAKE_LOG"'
echo "[13e] hung getprop is killed by the timeout and reported"
: >"$FAKE_LOG"; EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES" FAKE_GETPROP_HANG=1 STARTUP_LAUNCH_TIMEOUT_S=1)
SECONDS=0; run --device dev-1; DUR=$SECONDS
check "getprop timeout -> exit 1 with ERROR on stderr" '[ $RC -eq 1 ] && grep -q "^ERROR: adb getprop ro.product.model timed out after 1s" <<<"$OUT"'
check "getprop timeout fires promptly (<60s, not the 120s hang)" '[ "$DUR" -lt 60 ]'
check "no force-stop or launch attempted after hung getprop" '! grep -Eq "force-stop|am start" "$FAKE_LOG"'
echo "[13f] preflight (L4): tools + device state, rc 127 from getprop"
: >"$FAKE_LOG"; EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES" FAKE_STATE=offline)
run --device dev-1
check "offline device -> 1, clear message, nothing else ran" '[ $RC -eq 1 ] && grep -q "is not attached (adb get-state: .offline.)" <<<"$OUT" && ! grep -Eq "getprop|force-stop|am start" "$FAKE_LOG"'
EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES" FAKE_GETPROP_RC=127)
run --device dev-1
check "getprop rc 127 -> 1 with ERROR (not silently empty)" '[ $RC -eq 1 ] && grep -q "^ERROR: adb getprop ro.product.model failed (exit 127" <<<"$OUT"'
FARM="$ROOT/farm"; mkdir -p "$FARM"
for t in /usr/bin/*; do n="${t##*/}"; case "$n" in adb|flutter|timeout) ;; *) ln -sf "$t" "$FARM/$n" ;; esac; done
for missing in adb flutter timeout; do
  mkdir -p "$ROOT/fp-$missing"; cp "$ROOT/bin/adb" "$ROOT/bin/flutter" "$ROOT/fp-$missing/"; ln -sf /usr/bin/timeout "$ROOT/fp-$missing/timeout"
  rm -f "$ROOT/fp-$missing/$missing"
  EXTRA=(HOME="$ROOT/home" PATH="$ROOT/fp-$missing:$FARM" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES")
  run --device dev-1
  check "missing $missing -> 1 naming the tool" '[ $RC -eq 1 ] && grep -q "required tool not found on PATH: '"$missing"'" <<<"$OUT"'
done

echo "[13h] warm series: BACK + pidof before every sample, never force-stop/HOME"
printf '%s\n' 9999 900 700 800 600 750 >"$FAKE_TIMES"; : >"$FAKE_LOG"
EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES")
fn_warm() { OUT="$(env "${EXTRA[@]}" bash -c 'source "$1"; set +eu; shift; series_warm "$@"; echo "MEDIAN=$SERIES_MEDIAN"' _ "$TARGET" "$@" 2>&1)"; RC=$?; }
fn_warm dev-1 0 Warm
check "warm rc 0" '[ $RC -eq 0 ]'
check "priming + 5 launches" '[ "$(grep -c "am start -W" "$FAKE_LOG")" -eq 6 ]'
check "NO force-stop anywhere in warm" '! grep -q "force-stop" "$FAKE_LOG"'
check "NO HOME keyevent (that is hot)" '! grep -q "KEYCODE_HOME" "$FAKE_LOG"'
check "5 KEYCODE_BACK" '[ "$(grep -c "^-s dev-1 shell input keyevent KEYCODE_BACK$" "$FAKE_LOG")" -eq 5 ]'
check "5 pidof checks of the package" '[ "$(grep -c "^-s dev-1 shell pidof com.beautica.beautica_mobile$" "$FAKE_LOG")" -eq 5 ]'
check "every sample launch preceded by pidof, itself preceded by BACK" '[ "$(awk "/am start -W/ && NR>1 {if (p2 ~ /KEYCODE_BACK/ && p1 ~ /pidof/) ok++} {p2=p1; p1=\$0} END{print ok+0}" "$FAKE_LOG")" -eq 5 ]'
check "median of the 5 samples (priming excluded) = 750" 'grep -q "^MEDIAN=750$" <<<"$OUT" && grep -q "samples: 900 700 800 600 750" <<<"$OUT"'
echo "[13i] killed process -> sample INVALID, retried"
printf '%s\n' 9999 8888 900 700 800 600 750 >"$FAKE_TIMES"; : >"$FAKE_LOG"; echo 1 >"$ROOT/pf"
EXTRA+=(FAKE_PIDOF_FAILS="$ROOT/pf"); fn_warm dev-1 0 Warm
check "invalid reported, run succeeds with 5 valid samples" '[ $RC -eq 0 ] && grep -q "sample 1 INVALID" <<<"$OUT" && grep -q "samples: 900 700 800 600 750" <<<"$OUT"'
check "retry relaunched the app (7 launches) and still no force-stop" '[ "$(grep -c "am start -W" "$FAKE_LOG")" -eq 7 ] && ! grep -q force-stop "$FAKE_LOG"'
echo "[13j] process that keeps dying -> exit 1 after 3 tries"
printf '%s\n' 1 2 3 4 5 6 7 8 9 >"$FAKE_TIMES"; : >"$FAKE_LOG"; echo 99 >"$ROOT/pf"; fn_warm dev-1 0 Warm
check "gives up with exit 1 and a clear error" '[ $RC -eq 1 ] && grep -q "invalid 3 times" <<<"$OUT" && ! grep -q "^MEDIAN=" <<<"$OUT"'
EXTRA=(HOME="$ROOT/home")

echo "[13g] history under a symlinked ANCESTOR is refused (L3)"
mkdir -p "$ROOT/home/real"; ln -s "$ROOT/home/real" "$ROOT/home/lnk"
EXTRA=(HOME="$ROOT/home" STARTUP_HISTORY_DIR="$ROOT/home/lnk/sub/hist")
fn write_history 1 1 m
check "symlinked ancestor under HOME: warns, rc 0, wrote nothing" '[ $RC -eq 0 ] && grep -q "symlink" <<<"$OUT" && [ -z "$(ls -A "$ROOT/home/real")" ]'
EXTRA=(HOME="$ROOT/home" STARTUP_HISTORY_DIR="$ROOT/home/ok/sub/hist")
fn write_history 1 1 m
check "plain nested dir under HOME still works" '[ $RC -eq 0 ] && [ -f "$ROOT/home/ok/sub/hist/startup-history-v2.csv" ]'
EXTRA=(HOME="$ROOT/home" PATH="$ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAKE_TIMES="$FAKE_TIMES" STARTUP_LAUNCH_TIMEOUT_S=abc)
run --check 1 1; check "bad launch timeout env -> 64" '[ $RC -eq 64 ]'
EXTRA=(HOME="$ROOT/home")

echo "[14] N4 user-supplied --info/--timeline paths are scrubbed"
ESC=$'\033'; BADI="$ROOT/ev${ESC}[31mil${ESC}]0;x"
run --check 1 1 --info "$BADI"
check "missing --info with ESC in name: no ESC byte, exit 1" '[ $RC -eq 1 ] && ! grep -q "$ESC" <<<"$OUT" && grep -q "start_up_info.json not found" <<<"$OUT"'
printf '{}' >"$BADI"; run --check 1 1 --info "$BADI"
check "info without timeToFirstFrameMicros, ESC in name: no ESC byte" '[ $RC -eq 1 ] && ! grep -q "$ESC" <<<"$OUT" && grep -q "timeToFirstFrameMicros missing" <<<"$OUT"'
rm -f "$BADI"; run --check 1 1 --timeline "$BADI"
check "missing --timeline with ESC in name: no ESC byte" '! grep -q "$ESC" <<<"$OUT" && grep -q "timeline not found" <<<"$OUT"'
printf '{not json' >"$BADI"; run --check 1 1 --timeline "$BADI"
check "unparsable --timeline with ESC in name: no ESC byte" '! grep -q "$ESC" <<<"$OUT" && grep -q "could not parse" <<<"$OUT"'
printf '{"traceEvents":[]}' >"$BADI"; run --check 1 1 --timeline "$BADI"
check "slice-less --timeline with ESC in name: no ESC byte" '! grep -q "$ESC" <<<"$OUT" && grep -q "no boot:\* slices" <<<"$OUT"'

echo "[15] N5 history append is symlink-safe (mv -T, no write-through) and keeps rows"
H5="$ROOT/h5"; EXTRA=(HOME="$ROOT/home" STARTUP_HISTORY_DIR="$H5")
fn write_history 1 2 m; fn write_history 3 4 m
check "two writes -> header + 2 rows, 600, no .tmp leftovers" '[ "$(wc -l <"$H5/startup-history-v2.csv")" -eq 3 ] && [ "$(sed -n 1p "$H5/startup-history-v2.csv")" = "date,sha,model,cold_ms,warm_ms" ] && [ "$(stat -c %a "$H5/startup-history-v2.csv")" = 600 ] && ! ls -A "$H5" | grep -q "^\.tmp"'
FD="$ROOT/fakedate"; mkdir -p "$FD"
printf '#!/bin/sh\nrm -f "$PLANT"; ln -s "$VICTIM" "$PLANT"\nexec /bin/date "$@"\n' >"$FD/date"; chmod +x "$FD/date"
: >"$ROOT/victim2"
EXTRA=(HOME="$ROOT/home" STARTUP_HISTORY_DIR="$H5" PATH="$FD:$PATH" PLANT="$H5/startup-history-v2.csv" VICTIM="$ROOT/victim2")
fn write_history 5 6 m
check "symlink planted AFTER the check (TOCTOU): victim untouched, link replaced by a regular file" '[ $RC -eq 0 ] && [ ! -s "$ROOT/victim2" ] && [ -f "$H5/startup-history-v2.csv" ] && [ ! -L "$H5/startup-history-v2.csv" ]'
EXTRA=(HOME="$ROOT/home")

echo "[16] --no-trace: accepted by the parser; install helper builds then adb-installs, no flutter run"
run --check 1500 500 --no-trace; check "--no-trace accepted in --check mode" '[ $RC -eq 0 ]'
FB="$ROOT/fakebin"; mkdir -p "$FB" "$ROOT/m/build/app/outputs/flutter-apk"; : >"$ROOT/m/build/app/outputs/flutter-apk/app-profile.apk"
printf '#!/bin/sh\necho "flutter $*" >>"$LOG"\n' >"$FB/flutter"; printf '#!/bin/sh\necho "adb $*" >>"$LOG"\n' >"$FB/adb"; chmod +x "$FB/flutter" "$FB/adb"
EXTRA=(HOME="$ROOT/home" PATH="$FB:$PATH" LOG="$ROOT/calls.log" MOBILE_DIR="$ROOT/m")
: >"$ROOT/calls.log"; OUT="$(env "${EXTRA[@]}" bash -c 'source "$1"; set +eu; MOBILE_DIR="$2"; install_profile_no_trace SER' _ "$TARGET" "$ROOT/m" 2>&1)"; RC=$?
check "build apk --profile then adb -s SER install -r; never flutter run" '[ $RC -eq 0 ] && grep -q "^flutter build apk --profile" "$ROOT/calls.log" && grep -q "^adb -s SER install -r .*app-profile.apk" "$ROOT/calls.log" && ! grep -q "flutter run" "$ROOT/calls.log"'
EXTRA=(HOME="$ROOT/home")

echo
echo "RESULT: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
