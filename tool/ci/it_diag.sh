#!/usr/bin/env bash
# Emulator-leg memory hygiene + diagnostics for the full-suite shard attempts
# (PR #137, 2026-11-06). Every shard attempt lost its emulator 1-3 min in, with
# no relaunch (docs/ci/emulator-integration.md#emulator-device-loss). Leading
# hypothesis: host memory pressure -- a 3 GB Gradle daemon + a 1.5 GB Kotlin
# daemon left alive by the pre-build next to the 4 GB emulator. This script
# frees those daemons and records the evidence that confirms or refutes it.
#
#   it_diag.sh stop-build-daemons
#       Stops the Gradle daemon(s) and the Kotlin compile daemon. Never fails.
#   it_diag.sh run <dir> -- <command...>
#       Streams `adb logcat` to <dir>/logcat.txt and samples host memory
#       (free -m + top RSS, every IT_DIAG_INTERVAL s, default 15) to
#       <dir>/host-mem.txt while <command> runs; afterwards dumps
#       `adb logcat -d -t 2000` to <dir>/logcat-tail.txt and runs `host <dir>`
#       (the emulator is still up at that point, so its RSS is visible), then
#       copies /tmp/android-runner/emu-crash-*.db (if any) into <dir>, then
#       prints a 3-line verdict aid to the step log (adb device state,
#       emulator process alive/gone, min MemAvailable / max swap used). Exits
#       with <command>'s exit code -- the diagnostics never change a verdict.
#       Every adb call after the command is BOUNDED (IT_DIAG_ADB_TIMEOUT):
#       `adb logcat` waits for the device forever ("- waiting for device -")
#       once the emulator is offline, which hung all 8 shards of PR #137 run
#       42230622003 for 52 min after their verdict.
#   it_diag.sh host <dir>
#       Prints (and saves to <dir>/host.txt) free -m, the kernel OOM-killer
#       lines and the top RSS processes. Never fails.
#
# env: ADB (default `adb`), IT_DIAG_INTERVAL (seconds, default 15),
#      IT_DIAG_ADB_TIMEOUT (seconds per post-run adb call, default 20),
#      IT_DIAG_ANDROID_DIR (Gradle project for --stop, default `android`),
#      IT_DIAG_CRASH_GLOB (emulator crash dumps to keep, default
#      /tmp/android-runner/emu-crash-*.db).
set -uo pipefail
adb_bin="${ADB:-adb}"
adb_t="${IT_DIAG_ADB_TIMEOUT:-20}"
[[ "$adb_t" =~ ^[1-9][0-9]*$ ]] || adb_t=20
# adb with a hard bound: never waits for an offline/vanished device.
adb_bounded() { timeout --signal=KILL "$adb_t" "$adb_bin" "$@"; }
# Kill a background job (and its direct children), never wait unbounded.
stop_bg() {
  pkill -KILL -P "$1" 2>/dev/null || true
  kill -KILL "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

top_rss() { ps -eo rss,comm --sort=-rss 2>/dev/null | head -15 || true; }

case "${1:-}" in
  stop-build-daemons)
    gdir="${IT_DIAG_ANDROID_DIR:-android}"
    if [ -x "$gdir/gradlew" ]; then
      (cd "$gdir" && ./gradlew --stop -q) || true
    fi
    pkill -f KotlinCompileDaemon || true
    echo "it_diag: build daemons stopped (Gradle --stop + KotlinCompileDaemon)."
    exit 0
    ;;
  run)
    dir="${2:?dir}"
    [ "${3:-}" = "--" ] || { echo "::error::it_diag run: usage: it_diag.sh run <dir> -- <command...>"; exit 2; }
    shift 3
    [ "$#" -ge 1 ] || { echo "::error::it_diag run: no command"; exit 2; }
    interval="${IT_DIAG_INTERVAL:-15}"
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=15
    mkdir -p "$dir"
    "$adb_bin" logcat -v threadtime >"$dir/logcat.txt" 2>&1 </dev/null &
    logcat_pid=$!
    (
      while :; do
        echo "=== $(date -u +%FT%TZ)"
        free -m 2>/dev/null || true
        top_rss
        sleep "$interval"
      done
    ) >"$dir/host-mem.txt" 2>&1 </dev/null &
    sampler_pid=$!
    rc=0
    "$@" || rc=$?
    stop_bg "$sampler_pid"
    stop_bg "$logcat_pid"
    adb_bounded logcat -d -t 2000 >"$dir/logcat-tail.txt" 2>&1 </dev/null \
      || echo "it_diag: adb logcat -d gave up after ${adb_t}s (device offline/gone)" >>"$dir/logcat-tail.txt"
    timeout --signal=KILL 60 bash "${BASH_SOURCE[0]}" host "$dir" || true
    # Emulator crash dumps (host renderer death): keep them in the uploaded
    # artifact. Tolerates none; bounded; never changes the verdict.
    for crash in ${IT_DIAG_CRASH_GLOB:-/tmp/android-runner/emu-crash-*.db}; do
      [ -f "$crash" ] || continue
      timeout --signal=KILL 30 cp -- "$crash" "$dir/" 2>/dev/null || true
    done
    # Verdict aid: offline + emulator alive = guest stall (host contention);
    # emulator gone = host-side crash (renderer / OOM killer, see host.txt).
    dev="$(adb_bounded devices 2>/dev/null | grep -E '^emulator-' | tr '\t' ' ' | paste -sd ';' -)"
    emu="$(ps -eo pid,stat,etimes,rss,args 2>/dev/null | grep -E '[q]emu-system' | cut -c1-120 | head -1)"
    echo "it_diag: adb devices after the run: ${dev:-<no emulator listed>}"
    echo "it_diag: emulator process after the run: ${emu:-<gone>}"
    awk '$1=="Mem:"{if(min==""||$NF<min)min=$NF} $1=="Swap:"{if($3>max)max=$3}
      END{printf "it_diag: host during the run: min available %s MiB, max swap used %s MiB\n",(min==""?"?":min),(max==""?"?":max)}' \
      "$dir/host-mem.txt" 2>/dev/null || true
    exit "$rc"
    ;;
  host)
    dir="${2:?dir}"
    mkdir -p "$dir" 2>/dev/null || true
    {
      echo "=== free -m"
      free -m 2>/dev/null || true
      echo "=== kernel OOM killer (dmesg)"
      timeout --signal=KILL 20 sudo -n dmesg -T 2>/dev/null | grep -iE 'oom|killed process' | tail -20 || true
      echo "=== top RSS (KiB)"
      top_rss
    } 2>&1 | tee "$dir/host.txt" || true
    exit 0
    ;;
  *)
    echo "::error::it_diag: unknown subcommand '${1:-}' (stop-build-daemons | run | host)"
    exit 2
    ;;
esac
