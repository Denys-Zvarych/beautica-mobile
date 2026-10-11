#!/usr/bin/env bash
# ================================================
# scripts/perf/measure_jank.sh
#
# Phase 076 (10.2) / mobile-perf MP1-MP3, MP12: measure scroll jank on the four
# heaviest lists on a real device and fail if a frame budget is blown. Modelled
# on measure_startup.sh (same hardening: validated serial, timeouts on adb,
# sanitised device output, symlink-safe history outside the repo).
#
# Usage:
#   scripts/perf/measure_jank.sh --device <serial> [--enforce]
#   scripts/perf/measure_jank.sh --summarize <response.json> [--model <name>] [--qemu <0|1>]
#       device-free: parse + tabulate + budget-check an existing
#       integration_response_data.json. `--check` is an alias.
#
# What a device run does:
#   1. from beautica-mobile/, runs
#        flutter drive --profile --driver=test_driver/integration_test.dart \
#          --target=integration_test/perf/scroll_jank_test.dart -d <serial>
#      (profile = AOT, asserts stripped, release-like). The test flings each of
#      the four surfaces (my-bookings, search-results, services-list,
#      salon-board) under binding.watchPerformance; the driver writes the
#      per-surface FrameTimingSummarizer summaries to
#      build/integration_response_data.json.
#   2. copies that JSON to ~/.cache/beautica-history/jank/<date>-<sha>.json
#      (dir 700, file 600; refused if the dir or any ancestor under $HOME is a symlink; an existing
#      name gets a -2, -3, ... suffix so a second run never overwrites the
#      first). Never writes into the repo.
#   3. prints a per-surface table and applies the budget.
#
# Table columns (ms): frames, p50/p90/worst frame BUILD time, r90/rworst frame
# RASTERIZER time. p50 is the lower-middle of `frame_build_times` (microseconds);
# without that list it falls back to the average and the row is marked `~`.
#
# Budget: p90 AND worst of BOTH build and rasterizer time must be < the frame
# budget, and frame_count >= JANK_MIN_FRAMES, on every one of the four surfaces;
# a missing surface, an unreadable summary or a non-numeric figure is a FAILURE
# (never silently skipped). The budget is 1000/Hz of the device display
# (`dumpsys display`; 60 Hz + a warning when unreadable) unless JANK_BUDGET_MS is
# set; `--summarize` uses 16 unless JANK_BUDGET_MS or `--hz N` is given. The drive
# runs JANK_REPEATS times (default 3) and every figure gated is the median of the
# per-run values (upper median for an even count; frames: the minimum). `--summarize` accepts several files (repeat
# the flag). A dirty tree suffixes the history name `-dirty-<7 hex of git diff>`.
#
# By default the device run passes --dart-define=JANK_ENFORCE=false to the test,
# so a baseline over budget still WRITES its JSON (the driver drops response data
# when a test fails) and THIS script's table is the gate. Pass --enforce to make
# the in-test assertion fire as well.
#
# Exit codes: 0 within budget, 1 over budget / measurement failure, 64 usage.
#
# Env vars (optional):
#   JANK_BUDGET_MS        default: 1000/refresh-rate (16 for --summarize); strictly-less-than, ms
#   JANK_MIN_FRAMES       default 60     (fewer frames in a surface run = FAIL)
#   JANK_REPEATS          default 3      (drive runs per invocation, 1..20)
#   JANK_DRIVE_TIMEOUT_S  default 1500   (whole `flutter drive` run)
#   JANK_ADB_TIMEOUT_S    default 60     (per adb call)
#   JANK_HISTORY_DIR      default ~/.cache/beautica-history/jank
#   JANK_HISTORY_MAX_TRIES default 1000  (cap on attempts to create a uniquely named history file; positive integer; tests lower it)
#   JANK_MOBILE_DIR       default <this repo root> (override is for tests)
#   ANDROID_SERIAL        default device (set up by connect_adb.sh)
# Budgets are calibrated for a mid-tier physical device in profile mode;
# emulators get a warning.
# ================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MOBILE_REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
MOBILE_DIR="${JANK_MOBILE_DIR:-$MOBILE_REPO_DIR}"
BUDGET="${JANK_BUDGET_MS:-16}"
DRIVE_TIMEOUT="${JANK_DRIVE_TIMEOUT_S:-1500}"
ADB_TIMEOUT="${JANK_ADB_TIMEOUT_S:-60}"
MIN_FRAMES="${JANK_MIN_FRAMES:-60}"
REPEATS="${JANK_REPEATS:-3}"
# JANK_NO_DDS=1 adds `--no-dds` to flutter drive: needed when adb is a REMOTE server
# (ADB_SERVER_SOCKET=tcp:host:port) so the on-device test can reach its own VM service
# (the host-side DDS port is unreachable from the phone). Default off.
DRIVE_EXTRA=()
[[ "${JANK_NO_DDS:-0}" == 1 ]] && DRIVE_EXTRA=(--no-dds)
MAX_JSON_BYTES=$((8 * 1024 * 1024))
SURFACES=(my-bookings search-results services-list salon-board)

usage() { awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; }
die64() { echo "$*" >&2; exit 64; }

# valid_serial <s> -> 0 if safe to pass to `adb -s`.
valid_serial() { [[ "$1" =~ ^[A-Za-z0-9._:-]+$ && "$1" != -* ]]; }

# sanitize_model <raw> -> printable-safe name (no ANSI/control/CSV chars).
sanitize_model() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._ -'; }

# scrub_raw: strip every byte but TAB, LF and printable ASCII.
scrub_raw() { tr -cd '\11\12\40-\176'; }

# device_warnings <model> <qemu 0|1>
device_warnings() {
  if [[ "$2" == 1 ]]; then echo "WARNING: device is an emulator; budgets are calibrated for a mid-tier physical device in profile mode" >&2; fi
  return 0
}

# adb_t <adb args...>: adb under the timeout; a timeout prints a clear message and returns 124.
adb_t() {
  local rc=0
  timeout --kill-after=5 "$ADB_TIMEOUT" adb "$@" || rc=$?
  if [[ "$rc" == 124 || "$rc" == 137 ]]; then
    echo "ERROR: adb ${*} timed out after ${ADB_TIMEOUT}s (device hung or adb stalled)" >&2
    return 124
  fi
  return "$rc"
}

# getprop_t <serial> <prop>: echoes the CR-stripped, scrubbed value; returns 1 only on timeout.
getprop_t() {
  local v rc=0
  v="$(adb_t -s "$1" shell getprop "$2" 2>/dev/null)" || rc=$?
  if (( rc == 124 )); then
    echo "ERROR: adb getprop $2 timed out after ${ADB_TIMEOUT}s" >&2
    return 1
  fi
  if (( rc != 0 )); then
    echo "ERROR: adb getprop $2 failed (exit $rc; 127 means adb is not installed)" >&2
    return 1
  fi
  printf '%s' "$v" | tr -d '\r' | scrub_raw
}

# summarize_json <file...> -> prints the table + verdict, returns 0 within budget, 1 otherwise.
# Several files = several repeat runs of the same drive; every per-surface figure is the
# UPPER-middle MEDIAN of the per-run values (frames: the MINIMUM, so a thin run cannot hide).
# For an even number of runs the upper of the two middle values is gated (conservative).
# All parsing happens in python3 (no jq dependency, strict number validation).
summarize_json() {
  local f size
  for f in "$@"; do
    [[ -f "$f" && ! -L "$f" ]] || { echo "ERROR: not a regular file: $(printf '%s' "$f" | scrub_raw)" >&2; return 1; }
    size="$(stat -c %s -- "$f" 2>/dev/null || echo 0)"
    (( size > 0 && size <= MAX_JSON_BYTES )) || { echo "ERROR: $(printf '%s' "$f" | scrub_raw) is empty or larger than ${MAX_JSON_BYTES} bytes" >&2; return 1; }
  done
  python3 - "$BUDGET" "$MIN_FRAMES" "$#" "$@" "${SURFACES[@]}" <<'PY'
import json, math, re, sys

budget, min_frames, nfiles = float(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
paths = sys.argv[4:4 + nfiles]
required = sys.argv[4 + nfiles:]


def clean(s):
    return re.sub(r"[^A-Za-z0-9._-]", "", str(s))[:32]


def scrub(s):
    return re.sub(r"[^\x09\x0a\x20-\x7e]", "", str(s))


def num(v):
    """A finite, non-negative float, else None (bool is not a number here)."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    v = float(v)
    return v if math.isfinite(v) and v >= 0 else None


def p50_ms(summary):
    """(value_ms, estimated). Lower-middle of frame_build_times (us); else average."""
    times = summary.get("frame_build_times")
    if isinstance(times, list) and times:
        vals = [num(t) for t in times]
        if all(v is not None for v in vals):
            vals.sort()
            return vals[(len(vals) + 1) // 2 - 1] / 1000.0, False
    avg = num(summary.get("average_frame_build_time_millis"))
    return avg, True


def med(xs):
    """UPPER median (conservative for the gate: an even repeat count never rounds down)."""
    xs = sorted(xs)
    return xs[len(xs) // 2]


runs, failures = {}, []
for path in paths:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as e:
        print("ERROR: cannot parse %s: %s" % (scrub(path), clean(type(e).__name__)), file=sys.stderr)
        sys.exit(1)
    if not isinstance(data, dict):
        print("ERROR: %s: top level is not an object" % scrub(path), file=sys.stderr)
        sys.exit(1)
    for raw_key, summary in data.items():
        if not isinstance(raw_key, str) or not raw_key.endswith("_scroll"):
            continue
        key = clean(raw_key[: -len("_scroll")])
        if not isinstance(summary, dict):
            failures.append("%s: summary is not an object" % key)
            continue
        p90 = num(summary.get("90th_percentile_frame_build_time_millis"))
        worst = num(summary.get("worst_frame_build_time_millis"))
        r90 = num(summary.get("90th_percentile_frame_rasterizer_time_millis"))
        rworst = num(summary.get("worst_frame_rasterizer_time_millis"))
        p50, est = p50_ms(summary)
        frames = summary.get("frame_count")
        frames = frames if isinstance(frames, int) and not isinstance(frames, bool) and frames >= 0 else None
        if None in (p90, worst, p50, r90, rworst):
            failures.append("%s: p50/p90/worst/rasterizer p90/worst missing or not a finite number" % key)
            continue
        runs.setdefault(key, []).append((frames, p50, est, p90, worst, r90, rworst))

for key in sorted(runs):
    if len(runs[key]) != nfiles and not any(f.startswith(key + ":") for f in failures):
        failures.append("surface %s missing from %d of %d runs" % (key, nfiles - len(runs[key]), nfiles))

for s in required:
    if s not in runs and not any(f.startswith(s + ":") for f in failures):
        failures.append("%s: surface missing from the response data" % s)

print("%-16s %7s %9s %9s %10s %9s %10s  %s" % ("surface", "frames", "p50 ms", "p90 ms", "worst ms", "r90 ms", "rworst ms", "verdict"))
over, any_est = False, False
for key in sorted(runs, key=lambda k: (k not in required, required.index(k) if k in required else 0, k)):
    rs = runs[key]
    fr = [r[0] for r in rs]
    frames = None if any(x is None for x in fr) else min(fr)
    est = any(r[2] for r in rs)
    any_est = any_est or est
    p50, p90, worst, r90, rworst = (med([r[i] for r in rs]) for i in (1, 3, 4, 5, 6))
    bad = []
    if frames is None or frames < min_frames:
        bad.append("too few frames (%s < %d)" % ("n/a" if frames is None else frames, min_frames))
    for label, v in (("p90", p90), ("worst", worst), ("r90", r90), ("rworst", rworst)):
        if not v < budget:
            bad.append("%s %.2f >= %g" % (label, v, budget))
    over = over or bool(bad)
    print("%-16s %7s %8.2f%s %9.2f %10.2f %9.2f %10.2f  %s" % (
        key, "n/a" if frames is None else frames, p50, "~" if est else " ", p90, worst, r90, rworst,
        "FAIL (%s)" % "; ".join(bad) if bad else "PASS"))
if any_est:
    print("~ p50 estimated from the average (summary had no frame_build_times)")
if nfiles > 1:
    print("figures are the median of %d runs (frames: the minimum)" % nfiles)
for f in failures:
    print("FAIL: %s" % f, file=sys.stderr)
if over or failures:
    print("FAIL: frame budget is p90 < %g ms and worst < %g ms (build AND rasterizer), >= %d frames, on every surface" % (budget, budget, min_frames), file=sys.stderr)
    sys.exit(1)
print("PASS: all %d surfaces within the %g ms frame budget" % (len(required), budget))
PY
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

# write_history <json> <sha> -> copies the response JSON into the history dir; never fails the run.
# Refuses a symlinked dir or ancestor; writes a mktemp file in the dir and hard-links it to the
# final name (ln fails if the name exists, even as a symlink), so no TOCTOU window overwrites.
write_history() {
  local hist_dir="${JANK_HISTORY_DIR:-$HOME/.cache/beautica-history/jank}"
  local base dest tmp n=1
  local max_tries="${JANK_HISTORY_MAX_TRIES:-1000}"
  [[ "$max_tries" =~ ^[1-9][0-9]*$ ]] || { echo "WARNING: JANK_HISTORY_MAX_TRIES must be a positive integer; using 1000" >&2; max_tries=1000; }
  if path_has_symlink "$hist_dir"; then
    echo "WARNING: history path is or sits under a symlink; refusing to write into $hist_dir" >&2
    return 0
  fi
  base="$(date +%F)-$(sanitize_model "$2" | tr -d ' ')"
  {
    (umask 077; mkdir -p "$hist_dir") && chmod 700 "$hist_dir"
    path_has_symlink "$hist_dir" && { echo "WARNING: history path is or sits under a symlink; refusing" >&2; return 0; }
    tmp="$(mktemp "$hist_dir/.tmp.XXXXXX" 2>/dev/null)" || tmp=""
    [[ -n "$tmp" ]] || { echo "WARNING: could not create a temp file in $hist_dir; history not written" >&2; return 0; }
    (cat -- "$1" >"$tmp") && chmod 600 "$tmp" || { rm -f -- "$tmp"; false; }
    dest="$hist_dir/$base.json"
    # ln fails if the name exists (even as a symlink). If it fails while the name is FREE (no hard
    # links on vfat/vboxsf, EPERM) fall back to cp -n. The attempt count is capped: a `||` list
    # disables set -e, so the cap must return explicitly rather than rely on a failing command.
    until ln -- "$tmp" "$dest" 2>/dev/null; do
      if [[ ! -e "$dest" && ! -L "$dest" ]] && cp -n -- "$tmp" "$dest" 2>/dev/null \
         && [[ -f "$dest" && ! -L "$dest" ]] && cmp -s -- "$tmp" "$dest"; then
        chmod 600 "$dest" 2>/dev/null || true
        break
      fi
      n=$((n + 1)); dest="$hist_dir/$base-$n.json"
      if (( n >= max_tries )); then
        rm -f -- "$tmp"
        echo "WARNING: gave up after $max_tries attempts to create a history file in $hist_dir (ln and cp both failed)" >&2
        return 0
      fi
    done
    rm -f -- "$tmp"
    echo "history: $dest"
  } || echo "WARNING: could not update history dir $hist_dir" >&2
  return 0
}

# preflight <serial>: required tools present and the device attached; exits 1 with a message otherwise.
preflight() {
  local t
  for t in adb flutter timeout; do
    command -v "$t" >/dev/null 2>&1 || { echo "ERROR: required tool not found on PATH: $t" >&2; exit 1; }
  done
  local st rc=0
  st="$(adb_t -s "$1" get-state 2>/dev/null | tr -d '\r' | scrub_raw)" || rc=$?
  if (( rc != 0 )) || [[ "$st" != device ]]; then
    echo "ERROR: device '$1' is not attached (adb get-state: '${st:-none}'); device bridge: the monorepo-root scripts/connect_adb.sh, outside this repo, if you use it" >&2
    exit 1
  fi
}

# device_hz <serial>: echoes the display refresh rate in Hz (integer), 60 + a warning on any doubt.
device_hz() {
  local raw hz=""
  raw="$(adb_t -s "$1" shell dumpsys display 2>/dev/null | scrub_raw)" || raw=""
  hz="$(printf '%s\n' "$raw" | grep -Eo 'renderFrameRate[= ]+[0-9]+(\.[0-9]+)?' | sed -n '1p' | grep -Eo '[0-9]+(\.[0-9]+)?$')" || hz=""
  [[ -n "$hz" ]] || hz="$(printf '%s\n' "$raw" | grep -Eo 'fps=[0-9]+(\.[0-9]+)?' | sed -n '1p' | cut -d= -f2)" || hz=""
  if [[ "$hz" =~ ^[0-9]+(\.[0-9]+)?$ ]] && python3 -c 'import sys; sys.exit(0 if 24 <= float(sys.argv[1]) <= 240 else 1)' "$hz"; then
    python3 -c 'import sys; print(round(float(sys.argv[1])))' "$hz"
  else
    echo "WARNING: could not read the device refresh rate from 'dumpsys display'; assuming 60 Hz" >&2
    echo 60
  fi
}

main() {
  [[ "$BUDGET" =~ ^[1-9][0-9]*(\.[0-9]+)?$ ]] || die64 "JANK_BUDGET_MS must be a positive number"
  [[ "$DRIVE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die64 "JANK_DRIVE_TIMEOUT_S must be a positive integer"
  [[ "$ADB_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die64 "JANK_ADB_TIMEOUT_S must be a positive integer"
  [[ "$MIN_FRAMES" =~ ^[1-9][0-9]*$ ]] || die64 "JANK_MIN_FRAMES must be a positive integer"
  [[ "$REPEATS" =~ ^[1-9][0-9]*$ ]] && (( REPEATS <= 20 )) || die64 "JANK_REPEATS must be an integer in 1..20"

  local mode=device serial="${ANDROID_SERIAL:-}" model="" qemu="" enforce=false hz=""
  local -a jsons=()
  while (( $# )); do
    case "$1" in
      --device) [[ $# -ge 2 ]] || die64 "--device needs a serial"; serial="$2"; shift 2 ;;
      --summarize|--check) [[ $# -ge 2 ]] || die64 "$1 needs a json file"; mode=summarize; jsons+=("$2"); shift 2 ;;
      --model) [[ $# -ge 2 ]] || die64 "--model needs a name"; model="$2"; shift 2 ;;
      --qemu) [[ $# -ge 2 ]] || die64 "--qemu needs 0|1"; qemu="$2"; shift 2 ;;
      --hz) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die64 "--hz needs an integer"; hz="$2"; shift 2 ;;
      --enforce) enforce=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die64 "unknown argument: $1" ;;
    esac
  done

  if [[ "$mode" == summarize ]]; then
    [[ -z "$qemu" || "$qemu" =~ ^[01]$ ]] || die64 "--qemu needs 0|1"
    model="$(sanitize_model "$model")"
    [[ -z "$model" ]] || device_warnings "$model" "${qemu:-0}"
    if [[ -n "$hz" && -z "${JANK_BUDGET_MS:-}" ]]; then BUDGET="$(python3 -c 'import sys; print(round(1000/float(sys.argv[1]), 2))' "$hz")"; fi
    summarize_json "${jsons[@]}" && exit 0 || exit 1
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

  if [[ -z "${JANK_BUDGET_MS:-}" ]]; then
    hz="$(device_hz "$serial")"
    BUDGET="$(python3 -c 'import sys; print(round(1000/float(sys.argv[1]), 2))' "$hz")"
    echo "==> display ${hz} Hz -> frame budget ${BUDGET} ms (override: JANK_BUDGET_MS)"
  fi

  local out_dir="${FLUTTER_TEST_OUTPUTS_DIR:-$MOBILE_DIR/build}"
  local resp="$out_dir/integration_response_data.json"
  [[ -d "$MOBILE_DIR" ]] || { echo "ERROR: mobile dir not found: $MOBILE_DIR" >&2; exit 1; }

  local sha dirty
  sha="$(git -C "$MOBILE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  dirty="$(git -C "$MOBILE_DIR" status --porcelain 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    sha="$sha-dirty-$( { git -C "$MOBILE_DIR" diff HEAD 2>/dev/null; printf '%s' "$dirty"; } | sha1sum | cut -c1-7)"
  fi

  local i rc keep_dir
  keep_dir="$(mktemp -d)"
  trap "rm -rf -- '$keep_dir'" EXIT
  for ((i = 1; i <= REPEATS; i++)); do
    rm -f -- "$resp"
    echo "==> flutter drive --profile (scroll jank, 4 surfaces, run $i/$REPEATS) on $serial [model: $model]"
    rc=0
    ( cd "$MOBILE_DIR" && timeout --kill-after=10 "$DRIVE_TIMEOUT" flutter drive --profile \
        --driver=test_driver/integration_test.dart \
        --target=integration_test/perf/scroll_jank_test.dart \
        --dart-define="JANK_ENFORCE=$enforce" \
        "${DRIVE_EXTRA[@]}" \
        -d "$serial" ) || rc=$?
    if (( rc == 124 || rc == 137 )); then
      echo "ERROR: flutter drive timed out after ${DRIVE_TIMEOUT}s (device hung or build stalled)" >&2
      exit 1
    fi
    if (( rc != 0 )); then
      echo "ERROR: flutter drive failed (exit $rc); no frame data is trustworthy" >&2
      exit 1
    fi
    [[ -f "$resp" && ! -L "$resp" ]] || { echo "ERROR: flutter drive wrote no $resp" >&2; exit 1; }
    cp -- "$resp" "$keep_dir/run-$i.json"
    write_history "$resp" "$sha"
    jsons+=("$keep_dir/run-$i.json")
  done
  summarize_json "${jsons[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
