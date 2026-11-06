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
#       (the emulator is still up at that point, so its RSS is visible). Exits
#       with <command>'s exit code -- the diagnostics never change a verdict.
#   it_diag.sh host <dir>
#       Prints (and saves to <dir>/host.txt) free -m, the kernel OOM-killer
#       lines and the top RSS processes. Never fails.
#
# env: ADB (default `adb`), IT_DIAG_INTERVAL (seconds, default 15),
#      IT_DIAG_ANDROID_DIR (Gradle project for --stop, default `android`).
set -uo pipefail
adb_bin="${ADB:-adb}"

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
    kill "$sampler_pid" "$logcat_pid" 2>/dev/null || true
    wait "$sampler_pid" "$logcat_pid" 2>/dev/null || true
    "$adb_bin" logcat -d -t 2000 >"$dir/logcat-tail.txt" 2>&1 </dev/null || true
    bash "${BASH_SOURCE[0]}" host "$dir" || true
    exit "$rc"
    ;;
  host)
    dir="${2:?dir}"
    mkdir -p "$dir" 2>/dev/null || true
    {
      echo "=== free -m"
      free -m 2>/dev/null || true
      echo "=== kernel OOM killer (dmesg)"
      sudo -n dmesg -T 2>/dev/null | grep -iE 'oom|killed process' | tail -20 || true
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
