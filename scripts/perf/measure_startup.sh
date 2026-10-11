#!/usr/bin/env bash
# ================================================
# scripts/perf/measure_startup.sh
#
# Phase 075 (10.1) / mobile-perf MP4: measure cold + warm start on a device and
# fail if over budget.  Mirrors measure_download_size.sh (history lives outside
# the repo).
#
# Usage:
#   scripts/perf/measure_startup.sh [--device <serial>]
#   scripts/perf/measure_startup.sh [--device <serial>] --no-trace
#       skip `flutter run --trace-startup` (it needs a VM-service attach, which hangs
#       through a REMOTE adb server, ADB_SERVER_SOCKET=tcp:host:port). Builds the profile
#       APK, `adb install -r`s it, measures the budgeted cold/warm medians only; no
#       start_up_info.json / boot:* slices are produced.
#   scripts/perf/measure_startup.sh --check <cold_ms[,ms...]> <warm_ms[,ms...]>
#                              [--info <start_up_info.json>]
#                              [--timeline <start_up_timeline.json>]
#                              [--model <name>] [--qemu <0|1>]
#       pure parse+compare, no device. Each list is median'd (lower-middle).
#
# Methodology (both budgeted figures are median-of-5 `am start -W` TotalTime, ms; they follow
# Android's definitions: cold = no process, warm = process alive + activity recreated):
#   0. `flutter run --profile --trace-startup` installs the profile build and
#      writes build/start_up_info.json + build/start_up_timeline.json
#      (attribution only, see below). Its own timing is NOT budgeted.
#   1. One discarded launch absorbs first-run dexopt / cache effects.
#   2. COLD = `am force-stop`, 3 s settle, launch. Process-cold, settled device.
#      Budget STARTUP_COLD_BUDGET_MS (default 2000).
#   3. WARM = process stays alive, activity is recreated: one priming launch (discarded), then per
#      sample `input keyevent KEYCODE_BACK` (finishes the activity), WARM_SETTLE_S wait for it to be
#      destroyed, `pidof` check, `am start -W`. NEVER force-stop (that is cold) and NEVER HOME (that
#      only resumes = hot). If `pidof` finds no process (Android killed it) the sample is reported
#      INVALID, the app is relaunched and the sample retried (max 3 tries, then exit 1).
#      Budget STARTUP_WARM_BUDGET_MS (default 800).
#   Page cache is not dropped (needs root); cold is therefore "settled", not a
#   reboot-cold start.
# Attribution (never budgeted): start_up_info.json timeToFirstFrameMicros starts
# at ENGINE init, so it excludes zygote fork + process/engine boot. The
# `boot:*` slices come from start_up_timeline.json (async b/e events emitted by
# lib/core/perf/startup_trace.dart); any slice > 100 ms is flagged (MP4: it
# opens a follow-up phase).
#
# Exit codes: 0 within budget (<=), 1 over budget / measurement failure, 64 usage.
#
# Env vars (optional):
#   STARTUP_COLD_BUDGET_MS  default 2000   (was STARTUP_COLD_BUDGET_US, retired)
#   STARTUP_WARM_BUDGET_MS  default 800
#   STARTUP_WARM_SETTLE_S   default 2     (wait after BACK for the activity to be destroyed)
#   STARTUP_LAUNCH_TIMEOUT_S default 60    (per `am start -W`; timeout = launch failed)
#   ANDROID_SERIAL          default device (set up by connect_adb.sh)
#
# Each device run appends "date,sha,model,cold_ms,warm_ms" to
# ~/.cache/beautica-history/startup-history-v2.csv (dir 700, file 600; skipped
# with a warning if either is a symlink). Never writes into the repo.
# Budgets are calibrated for the reference device (Pixel 6, physical); other
# models and emulators get a warning.
# ================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MOBILE_REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
MOBILE_DIR="$MOBILE_REPO_DIR"
PKG="com.beautica.beautica_mobile"
REF_MODEL="Pixel 6"
SLICE_WARN_US=100000
SAMPLES=5
LAUNCH_TIMEOUT="${STARTUP_LAUNCH_TIMEOUT_S:-60}"
COLD_BUDGET="${STARTUP_COLD_BUDGET_MS:-2000}"
WARM_BUDGET="${STARTUP_WARM_BUDGET_MS:-800}"
WARM_SETTLE="${STARTUP_WARM_SETTLE_S:-2}"
MAX_WARM_TRIES=3

usage() { awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; }
die64() { echo "$*" >&2; exit 64; }

# json_int <file> <key> -> integer value, empty if absent (no jq dependency).
json_int() {
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" "$1" | sed -n '1p'
}

# valid_serial <s> -> 0 if safe to pass to `adb -s`.
valid_serial() { [[ "$1" =~ ^[A-Za-z0-9._:-]+$ && "$1" != -* ]]; }

# median <n> <n> ... -> lower-middle element of the sorted list.
median() {
  local n=$# idx
  idx=$(( (n + 1) / 2 ))
  printf '%s\n' "$@" | sort -n | sed -n "${idx}p"
}

# parse_boot_slices <timeline.json> -> lines "boot:<name><TAB><duration_us>".
# Handles async b/e (id-paired; what StartupTrace emits), plus legacy B/E and X.
parse_boot_slices() {
  python3 - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ev = d.get("traceEvents", d) if isinstance(d, dict) else d
open_async, stack, out = {}, {}, []
for e in ev:
    n, ph = e.get("name", ""), e.get("ph")
    if not isinstance(n, str) or not n.startswith("boot:"):
        continue
    ts = e.get("ts")
    if ph == "b":
        open_async[(n, e.get("id"))] = ts
    elif ph == "e" and (n, e.get("id")) in open_async:
        out.append((n, ts - open_async.pop((n, e.get("id")))))
    elif ph == "B":
        stack.setdefault(n, []).append(ts)
    elif ph == "E" and stack.get(n):
        out.append((n, ts - stack[n].pop()))
    elif ph == "X" and "dur" in e:
        out.append((n, e["dur"]))
for n, us in out:
    print("%s\t%d" % (n, us))
PY
}

# report_slices <timeline.json> -> prints each boot:* duration, flags > 100 ms.
report_slices() {
  local f="$1" out n us any=0 sf
  sf="$(printf '%s' "$f" | scrub_raw)"
  if [[ ! -f "$f" ]]; then
    echo "boot:* slices UNAVAILABLE (no start_up_timeline.json): $sf; slice attribution is missing for this run"
    echo "WARNING: timeline not found: $sf (boot:* slices not captured)" >&2
    return 0
  fi
  out="$(parse_boot_slices "$f")" || { echo "WARNING: could not parse $sf" >&2; return 0; }
  echo "boot:* slices (attribution):"
  while IFS=$'\t' read -r n us; do
    [[ -n "$n" ]] || continue
    any=1
    if (( us > SLICE_WARN_US )); then
      printf '  %-18s %8d us  OVER 100 ms -> follow-up phase (MP4)\n' "$n" "$us"
    else
      printf '  %-18s %8d us\n' "$n" "$us"
    fi
  done <<<"$out"
  (( any )) || echo "WARNING: no boot:* slices in $sf (profile build? timeline stream off?)" >&2
  return 0
}

# sanitize_model <raw> -> printable-safe model name (no ANSI/control/CSV chars).
sanitize_model() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._ -'; }

# device_warnings <model> <qemu 0|1>
device_warnings() {
  if [[ "$2" == 1 ]]; then echo "WARNING: device is an emulator; budgets are calibrated for a physical $REF_MODEL" >&2; fi
  if [[ "$1" != "$REF_MODEL" ]]; then echo "WARNING: device model '$1' is not the reference '$REF_MODEL'; compare with care" >&2; fi
  return 0
}

# evaluate <cold_ms> <warm_ms> -> prints verdict, returns 0/1.
evaluate() {
  local cold="$1" warm="$2" rc=0
  echo "cold (force-stop, settled) TotalTime median: ${cold} ms  (budget ${COLD_BUDGET})"
  echo "warm (process alive, activity recreated) TotalTime median: ${warm} ms  (budget ${WARM_BUDGET})"
  if (( cold > COLD_BUDGET )); then echo "FAIL: cold start over budget by $(( cold - COLD_BUDGET )) ms" >&2; rc=1; fi
  if (( warm > WARM_BUDGET )); then echo "FAIL: warm start over budget by $(( warm - WARM_BUDGET )) ms" >&2; rc=1; fi
  (( rc )) || echo "PASS: within startup budget"
  return $rc
}

# path_has_symlink <dir>: 0 when the dir (or, for a dir under $HOME, ANY component between
# $HOME and it) is a symlink. Outside $HOME only the leaf is checked.
path_has_symlink() {
  local d="${1%/}" cur rel part
  [[ -L "$d" ]] && return 0
  [[ "$d" == "$HOME"/* ]] || return 1
  cur="${HOME%/}"; rel="${d#"$cur"/}"
  while [[ -n "$rel" ]]; do
    part="${rel%%/*}"
    cur="$cur/$part"
    [[ -L "$cur" ]] && return 0
    [[ "$rel" == */* ]] && rel="${rel#*/}" || rel=""
  done
  return 1
}

# write_history <cold_ms> <warm_ms> <model>; never fails the run, never follows symlinks.
write_history() {
  local hist_dir="${STARTUP_HISTORY_DIR:-$HOME/.cache/beautica-history}"
  local hist="$hist_dir/startup-history-v2.csv" sha model tmp
  if path_has_symlink "$hist_dir" || [[ -L "$hist" ]]; then
    echo "WARNING: history path is or sits under a symlink; refusing to write $hist" >&2
    return 0
  fi
  sha="$(git -C "$MOBILE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  model="$(sanitize_model "$3")"
  # Symlink-safe: build header + existing rows + the new row in a mktemp file inside the dir, then
  # rename it over the CSV with mv -T. rename(2) never follows a symlink at the destination, so a
  # link planted after the check above is replaced, never written through.
  {
    (umask 077; mkdir -p "$hist_dir") && chmod 700 "$hist_dir"
    path_has_symlink "$hist_dir" && { echo "WARNING: history path is or sits under a symlink; refusing" >&2; return 0; }
    tmp="$(mktemp "$hist_dir/.tmp.XXXXXX" 2>/dev/null)" || tmp=""
    [[ -n "$tmp" ]] || { echo "WARNING: could not create a temp file in $hist_dir; history not written" >&2; return 0; }
    {
      if [[ -f "$hist" && ! -L "$hist" ]]; then cat -- "$hist"; else echo "date,sha,model,cold_ms,warm_ms"; fi
      printf '%s,%s,%s,%s,%s\n' "$(date +%F)" "$sha" "$model" "$1" "$2"
    } >"$tmp" && chmod 600 "$tmp" && mv -T -- "$tmp" "$hist" || { rm -f -- "$tmp"; false; }
  } || echo "WARNING: could not update history file $hist" >&2
  return 0
}

# adb_t <adb args...>: adb under the launch timeout; a timeout prints a clear message and returns 124.
adb_t() {
  local rc=0
  timeout --kill-after=5 "$LAUNCH_TIMEOUT" adb "$@" || rc=$?
  if [[ "$rc" == 124 || "$rc" == 137 ]]; then
    echo "ERROR: adb ${*} timed out after ${LAUNCH_TIMEOUT}s (device hung or adb stalled)" >&2
    return 124
  fi
  return "$rc"
}

# getprop_t <serial> <prop>: echoes the CR-stripped value; returns 1 only on timeout.
getprop_t() {
  local v rc=0
  v="$(adb_t -s "$1" shell getprop "$2" 2>/dev/null)" || rc=$?
  if (( rc == 124 )); then
    echo "ERROR: adb getprop $2 timed out after ${LAUNCH_TIMEOUT}s" >&2
    return 1
  fi
  if (( rc != 0 )); then
    echo "ERROR: adb getprop $2 failed (exit $rc; 127 means adb is not installed)" >&2
    return 1
  fi
  printf '%s' "$v" | tr -d '\r'
}

# scrub_raw: strip every byte but TAB, LF and printable ASCII (no device-injected ANSI/OSC escapes).
scrub_raw() { tr -cd '\11\12\40-\176'; }

# launch_ms <serial> -> echoes TotalTime ms; on failure prints raw am output, returns 1.
launch_ms() {
  local raw t rc=0
  raw="$(timeout --kill-after=5 "$LAUNCH_TIMEOUT" adb -s "$1" shell am start -W -n "$PKG/.MainActivity" 2>&1)" || rc=$?
  raw="$(printf '%s' "$raw" | tr -d '\r')"
  if [[ "$rc" == 124 || "$rc" == 137 ]]; then
    echo "ERROR: launch failed: am start -W timed out after ${LAUNCH_TIMEOUT}s (device hung or adb stalled). Raw am output:" >&2
    printf '%s\n' "$raw" | scrub_raw | sed 's/^/  | /' >&2
    return 1
  fi
  t="$(printf '%s\n' "$raw" | sed -n 's/^TotalTime:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | sed -n '1p')"
  if [[ ! "$t" =~ ^[0-9]+$ ]]; then
    echo "ERROR: launch failed (app crashed, not installed, or am start -W gave no TotalTime). Raw am output:" >&2
    printf '%s\n' "$raw" | scrub_raw | sed 's/^/  | /' >&2
    return 1
  fi
  echo "$t"
}

# preflight <serial>: required tools present and the device attached; exits 1 with a message otherwise.
preflight() {
  local t st rc=0
  for t in adb flutter timeout; do
    command -v "$t" >/dev/null 2>&1 || { echo "ERROR: required tool not found on PATH: $t" >&2; exit 1; }
  done
  st="$(adb_t -s "$1" get-state 2>/dev/null | tr -d '\r' | scrub_raw)" || rc=$?
  if (( rc != 0 )) || [[ "$st" != device ]]; then
    echo "ERROR: device '$1' is not attached (adb get-state: '${st:-none}'); device bridge: the monorepo-root scripts/connect_adb.sh, outside this repo, if you use it" >&2
    exit 1
  fi
}

# series <serial> <settle_s> <label> -> sets SERIES_MEDIAN
series() {
  local serial="$1" settle="$2" label="$3" i t
  local -a times=()
  echo "==> $label x$SAMPLES (force-stop, ${settle}s settle, am start -W)"
  for ((i = 0; i < SAMPLES; i++)); do
    adb_t -s "$serial" shell am force-stop "$PKG" || { (( $? == 124 )) && exit 1; }
    sleep "$settle"
    t="$(launch_ms "$serial")" || exit 1
    times+=("$t")
  done
  echo "    samples: ${times[*]}"
  SERIES_MEDIAN="$(median "${times[@]}")"
}

# series_warm <serial> <settle_s> <label> -> sets SERIES_MEDIAN. Process stays alive, activity is
# recreated (BACK, not HOME, not force-stop). Each sample: BACK, settle, pidof, am start -W.
series_warm() {
  local serial="$1" settle="$2" label="$3" i tries pid t
  local -a times=()
  echo "==> $label x$SAMPLES (BACK, ${settle}s settle, pidof, am start -W; process stays alive)"
  launch_ms "$serial" >/dev/null || exit 1   # priming: activity up, process alive (discarded)
  for ((i = 0; i < SAMPLES; i++)); do
    tries=0
    while :; do
      adb_t -s "$serial" shell input keyevent KEYCODE_BACK || { (( $? == 124 )) && exit 1; }
      sleep "$settle"
      pid="$(adb_t -s "$serial" shell pidof "$PKG" 2>/dev/null | tr -d '\r' | scrub_raw)" || pid=""
      [[ "$pid" =~ ^[0-9]+([[:space:]][0-9]+)*$ ]] && break
      tries=$((tries + 1))
      echo "    sample $((i + 1)) INVALID (process not alive after BACK; Android killed it), try $tries/$MAX_WARM_TRIES" >&2
      (( tries < MAX_WARM_TRIES )) || { echo "ERROR: warm sample $((i + 1)) invalid $MAX_WARM_TRIES times; process keeps dying" >&2; exit 1; }
      launch_ms "$serial" >/dev/null || exit 1   # restore process + activity, then retry the sample
    done
    t="$(launch_ms "$serial")" || exit 1
    times+=("$t")
  done
  echo "    samples: ${times[*]}"
  SERIES_MEDIAN="$(median "${times[@]}")"
}

# install_profile_no_trace <serial>: build the profile APK from this tree and install it
# without a VM-service attach (works through a remote adb server).
install_profile_no_trace() {
  local serial="$1" apk="$MOBILE_DIR/build/app/outputs/flutter-apk/app-profile.apk"
  echo "==> Build + install profile APK (--no-trace) on $serial"
  ( cd "$MOBILE_DIR" && timeout --kill-after=10 900 flutter build apk --profile ) || { echo "ERROR: flutter build apk --profile failed" >&2; exit 1; }
  [[ -f "$apk" ]] || { echo "ERROR: $apk not produced" >&2; exit 1; }
  timeout --kill-after=10 300 adb -s "$serial" install -r "$apk" || { echo "ERROR: adb install failed" >&2; exit 1; }
}

main() {
  [[ "$LAUNCH_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die64 "STARTUP_LAUNCH_TIMEOUT_S must be a positive integer"
  [[ "$COLD_BUDGET" =~ ^[0-9]+$ ]] || die64 "STARTUP_COLD_BUDGET_MS must be an integer"
  [[ "$WARM_BUDGET" =~ ^[0-9]+$ ]] || die64 "STARTUP_WARM_BUDGET_MS must be an integer"
  [[ "$WARM_SETTLE" =~ ^[0-9]+$ ]] || die64 "STARTUP_WARM_SETTLE_S must be an integer"
  [[ -z "${STARTUP_COLD_BUDGET_US:-}" ]] || echo "WARNING: STARTUP_COLD_BUDGET_US is retired and ignored; use STARTUP_COLD_BUDGET_MS" >&2

  local no_trace=0
  local mode=device serial="${ANDROID_SERIAL:-}" check_cold="" check_warm="" info="" timeline="" model="" qemu=""
  while (( $# )); do
    case "$1" in
      --device) [[ $# -ge 2 ]] || die64 "--device needs a serial"; serial="$2"; shift 2 ;;
      --no-trace) no_trace=1; shift ;;
      --check)
        [[ $# -ge 3 ]] || die64 "--check needs <cold_ms> <warm_ms>"
        mode=check; check_cold="$2"; check_warm="$3"; shift 3 ;;
      --info) [[ $# -ge 2 ]] || die64 "--info needs a file"; info="$2"; shift 2 ;;
      --timeline) [[ $# -ge 2 ]] || die64 "--timeline needs a file"; timeline="$2"; shift 2 ;;
      --model) [[ $# -ge 2 ]] || die64 "--model needs a name"; model="$2"; shift 2 ;;
      --qemu) [[ $# -ge 2 ]] || die64 "--qemu needs 0|1"; qemu="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die64 "unknown argument: $1" ;;
    esac
  done

  if [[ "$mode" == check ]]; then
    local re='^[0-9]+(,[0-9]+)*$' cold warm
    [[ "$check_cold" =~ $re ]] || die64 "<cold_ms> must be integer(s), comma-separated"
    [[ "$check_warm" =~ $re ]] || die64 "<warm_ms> must be integer(s), comma-separated"
    IFS=, read -ra _c <<<"$check_cold"; IFS=, read -ra _w <<<"$check_warm"
    cold="$(median "${_c[@]}")"; warm="$(median "${_w[@]}")"
    model="$(sanitize_model "$model")"
    [[ -z "$model" ]] || device_warnings "$model" "${qemu:-0}"
    if [[ -n "$info" ]]; then
      [[ -f "$info" ]] || { echo "start_up_info.json not found: $(printf '%s' "$info" | scrub_raw)" >&2; exit 1; }
      local ttf; ttf="$(json_int "$info" timeToFirstFrameMicros)"
      [[ "$ttf" =~ ^[0-9]+$ ]] || { echo "timeToFirstFrameMicros missing in $(printf '%s' "$info" | scrub_raw)" >&2; exit 1; }
      echo "attribution only (starts at engine init): timeToFirstFrameMicros ${ttf} us"
    fi
    [[ -z "$timeline" ]] || report_slices "$timeline"
    evaluate "$cold" "$warm" && exit 0 || exit 1
  fi

  [[ -n "$serial" ]] || die64 "no device: pass --device <serial> or set ANDROID_SERIAL (device bridge: the monorepo-root scripts/connect_adb.sh, outside this repo, if you use it)"
  valid_serial "$serial" || die64 "invalid device serial (allowed: A-Za-z0-9._:- and not starting with '-')"

  preflight "$serial"
  model="$(getprop_t "$serial" ro.product.model)" || exit 1
  qemu="$(getprop_t "$serial" ro.kernel.qemu)" || exit 1
  [[ "$qemu" == 1 ]] || qemu="$(getprop_t "$serial" ro.boot.qemu)" || exit 1
  [[ "$qemu" == 1 ]] || qemu=0
  model="$(sanitize_model "$model")"
  [[ -n "$model" ]] || model=unknown
  device_warnings "$model" "$qemu"

  # --- install + attribution (not budgeted) ---
  info="$MOBILE_DIR/build/start_up_info.json"
  timeline="$MOBILE_DIR/build/start_up_timeline.json"
  rm -f -- "$info" "$timeline" "${FLUTTER_TEST_OUTPUTS_DIR:+$FLUTTER_TEST_OUTPUTS_DIR/start_up_timeline.json}"
  if (( no_trace )); then
    install_profile_no_trace "$serial"
  else
    echo "==> Install + trace (profile, --trace-startup) on $serial"
    ( cd "$MOBILE_DIR" && flutter run --profile --trace-startup -d "$serial" )
  fi

  # --- discarded warm-up launch (dexopt) ---
  echo "==> Warm-up launch (discarded)"
  adb_t -s "$serial" shell am force-stop "$PKG" || { (( $? == 124 )) && exit 1; }
  launch_ms "$serial" >/dev/null || exit 1

  local cold warm
  series "$serial" 3 "Cold start"; cold="$SERIES_MEDIAN"
  series_warm "$serial" "$WARM_SETTLE" "Warm start"; warm="$SERIES_MEDIAN"

  # --- attribution ---
  if (( no_trace )); then
    echo "NOTE: --no-trace: start_up_info.json / boot:* slice attribution NOT collected (no VM-service attach)"
  elif [[ -f "$info" ]]; then
    local ttf; ttf="$(json_int "$info" timeToFirstFrameMicros)"
    echo "attribution only (starts at engine init): timeToFirstFrameMicros ${ttf:-n/a} us"
  else
    echo "WARNING: flutter did not write $info" >&2
  fi
  # flutter_tools run_cold.dart writes to $FLUTTER_TEST_OUTPUTS_DIR when set, else build/.
  if [[ ! -f "$timeline" && -n "${FLUTTER_TEST_OUTPUTS_DIR:-}" && -f "$FLUTTER_TEST_OUTPUTS_DIR/start_up_timeline.json" ]]; then
    timeline="$FLUTTER_TEST_OUTPUTS_DIR/start_up_timeline.json"
  fi
  (( no_trace )) || report_slices "$timeline"

  write_history "$cold" "$warm" "$model"
  evaluate "$cold" "$warm"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
