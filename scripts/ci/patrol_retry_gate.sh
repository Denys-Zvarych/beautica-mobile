#!/usr/bin/env bash
# Patrol retry gate: decides whether a FAILED patrol attempt may be retried once.
#
#   patrol_retry_gate.sh <attempt-log>   exit 0 = retry, 1 = do NOT retry
#   patrol_retry_gate.sh --self-test     prints "SELF-TEST OK: ..." on success
#
# Retry ONLY a lost device / failed SDK download (infrastructure), never a test.
# Fail closed: anything not positively a lost-device signature, an unreadable or
# empty log, or ANY hard assertion marker (even next to a lost-device one) => 1.
# A bare `PATROL TIMED OUT` (a hang) also => 1, unless a HARD device-lost
# signature explains it (emulator died, patrol then hung on the dead adb link).
# why: docs/ci/patrol.md#patrol-retry
set -u

# Lost-device / SDK-install signatures (ERE, applied to the ANSI-stripped log).
RETRY_ANYWHERE="device '(emulator-[0-9]+)' not found|AdbCommandRejectedException|Failed to install the following (Android )?SDK (components|packages)"
# `device offline` counts only AFTER the gallery-seed line: before it, the emulator
# is still booting and the line is boot noise (the step is retried by the runner).
OFFLINE_RE="device offline"
SEED_RE="seeded"
# HARD assertion markers: a real test failure. Always veto, win over every retry
# signature. `Unhandled Exception` is scoped to the capital-E form: that is the
# Dart engine/test-runner spelling ("Unhandled Exception: ..."). The lowercase
# `Unhandled exception:` is the Dart CLI top-level handler, i.e. patrol_cli itself
# crashing on a dead adb link (ProcessException ... device not found) -> infra
# noise, so it is deliberately NOT a marker. Java/ddmlib/Gradle never emit either.
HARD_VETO_RE="EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|TestFailure|(^|[^[:alnum:]])(Expected|Actual):|AssertionError|Unhandled Exception"
# A hang. Vetoes UNLESS a hard device-lost signature is present (emulator died,
# patrol then hung until the timeout). `device offline` is NOT accepted here.
TIMEOUT_RE="PATROL TIMED OUT"
DEVICE_LOST_RE="device '(emulator-[0-9]+)' not found|AdbCommandRejectedException"

gate() {
  local log="$1" clean
  if [ ! -s "$log" ]; then
    echo "patrol-retry-gate: log missing or empty ($log) -> no retry"
    return 1
  fi
  clean="$(mktemp)"
  # Strip ANSI escapes and CRs so colour codes cannot split a signature.
  sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/\r//g' "$log" > "$clean"

  if grep -aEq "$HARD_VETO_RE" "$clean"; then
    echo "patrol-retry-gate: test-failure marker present -> no retry (fail closed)"
    rm -f "$clean"; return 1
  fi
  if grep -aEq "$TIMEOUT_RE" "$clean"; then
    if grep -aEq "$DEVICE_LOST_RE" "$clean"; then
      echo "patrol-retry-gate: timeout with a device-lost signature (emulator died, patrol hung) -> retry"
      rm -f "$clean"; return 0
    fi
    echo "patrol-retry-gate: timeout without a device-lost signature (hang) -> no retry (fail closed)"
    rm -f "$clean"; return 1
  fi
  if grep -aEq "$RETRY_ANYWHERE" "$clean"; then
    echo "patrol-retry-gate: lost-device / SDK-install signature -> retry"
    rm -f "$clean"; return 0
  fi
  if awk -v seed="$SEED_RE" -v off="$OFFLINE_RE" \
       'seen && $0 ~ off { found=1 } $0 ~ seed { seen=1 } END { exit !found }' "$clean"; then
    echo "patrol-retry-gate: 'device offline' after the seed line -> retry"
    rm -f "$clean"; return 0
  fi
  echo "patrol-retry-gate: no lost-device signature -> no retry"
  rm -f "$clean"; return 1
}

self_test() {
  local d fails=0
  d="$(mktemp -d)"
  local esc=$'\x1b'

  # expect <name> <want-rc> <file>
  expect() {
    local rc=0
    gate "$3" >/dev/null || rc=$?
    if [ "$rc" -ne "$2" ]; then
      echo "FAIL: $1 (want rc=$2, got rc=$rc)"; fails=$((fails + 1))
    fi
  }

  # 1 lost device (the PR #95 shape) -> retry
  printf '%s\n' 'seeded /sdcard/Pictures/beautica_avatar_fixture.jpg' \
    "Exception thrown during onAfterAll invocation: device 'emulator-5554' not found" \
    'com.android.ddmlib.AdbCommandRejectedException: device '"'emulator-5554'"' not found' > "$d/lost"
  expect "lost device" 0 "$d/lost"

  # 2 assertion failure -> no retry
  printf '%s\n' 'seeded /sdcard/x.jpg' \
    "══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞══" 'Expected: <2>' '  Actual: <1>' > "$d/assert"
  expect "assertion failure" 1 "$d/assert"

  # 3 assertion failure + lost device -> no retry (fail closed)
  { cat "$d/assert"; cat "$d/lost"; } > "$d/both"
  expect "assertion + lost device" 1 "$d/both"

  # 4 SDK-install failure -> retry
  printf '%s\n' '> Failed to install the following SDK components:' \
    '      platforms;android-33 Android SDK Platform 33' 'BUILD FAILED in 8s' > "$d/sdk"
  expect "sdk install failure" 0 "$d/sdk"

  # 5 clean pass -> no retry
  printf '%s\n' 'seeded /sdcard/x.jpg' '✅ avatar gallery pick (32s)' 'All tests passed!' > "$d/pass"
  expect "clean pass" 1 "$d/pass"

  # 6 device offline AFTER seed -> retry; BEFORE seed -> no retry
  printf '%s\n' 'seeded /sdcard/x.jpg' 'adb: device offline' > "$d/off_after"
  expect "device offline after seed" 0 "$d/off_after"
  printf '%s\n' 'adb: device offline' 'seeded /sdcard/x.jpg' 'tests ran' > "$d/off_before"
  expect "device offline before seed" 1 "$d/off_before"
  printf '%s\n' 'adb: device offline' > "$d/off_noseed"
  expect "device offline, no seed line" 1 "$d/off_noseed"

  # 7 timeout: a hang alone -> no retry; with a hard device-lost signature the
  #   emulator died and patrol hung on the dead link -> retry; an assertion wins
  printf '%s\n' 'seeded /sdcard/x.jpg' 'PATROL TIMED OUT after 1200s (rc=124).' > "$d/timeout_alone"
  expect "timeout alone" 1 "$d/timeout_alone"
  { cat "$d/lost"; printf '%s\n' 'PATROL TIMED OUT after 1200s (rc=124).'; } > "$d/timeout"
  expect "timeout + lost device" 0 "$d/timeout"
  { cat "$d/assert"; cat "$d/timeout"; } > "$d/timeout_assert"
  expect "timeout + lost device + assertion" 1 "$d/timeout_assert"
  printf '%s\n' 'seeded /sdcard/x.jpg' 'adb: device offline' 'PATROL TIMED OUT after 1200s (rc=124).' > "$d/timeout_off"
  expect "timeout + device offline (not a hard signature)" 1 "$d/timeout_off"

  # 7b Unhandled Exception: the lowercase patrol_cli crash on a dead adb link is
  #   infra noise next to a lost device -> retry; the capital-E engine form is
  #   an app/test failure -> no retry even with a lost device.
  { cat "$d/lost"; printf '%s\n' 'Unhandled exception:' \
      "ProcessException: adb: device 'emulator-5554' not found" '#0 _runAdb (package:patrol_cli/x.dart:1)'; } > "$d/unh_noise"
  expect "lost device + Unhandled exception (patrol_cli adb noise)" 0 "$d/unh_noise"
  { cat "$d/lost"; printf '%s\n' '[ERROR:flutter/runtime/dart_vm_initializer.cc(41)] Unhandled Exception: Bad state'; } > "$d/unh_real"
  expect "lost device + Unhandled Exception (engine)" 1 "$d/unh_real"

  # 8 unrelated failure, missing and empty logs -> no retry
  printf '%s\n' 'seeded /sdcard/x.jpg' 'some other build error' > "$d/other"
  expect "unrelated failure" 1 "$d/other"
  expect "missing log" 1 "$d/does-not-exist"
  : > "$d/empty"
  expect "empty log" 1 "$d/empty"

  # 9 ANSI colour codes inside a signature are stripped
  printf '%s\n' 'seeded /sdcard/x.jpg' "device ${esc}[31m'emulator-5554'${esc}[0m not found" > "$d/ansi"
  expect "ansi-split signature" 0 "$d/ansi"

  rm -rf "$d"
  if [ "$fails" -ne 0 ]; then
    echo "SELF-TEST FAILED: $fails case(s)"; return 1
  fi
  echo "SELF-TEST OK: patrol_retry_gate.sh"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  "") echo "usage: $0 <attempt-log> | --self-test" >&2; exit 2 ;;
  *) gate "$1"; exit $? ;;
esac
