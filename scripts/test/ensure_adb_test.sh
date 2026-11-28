#!/usr/bin/env bash
# Self-test of tool/ci/ensure_adb.sh (phase 566 Scope 8a) against a fake Android SDK.
# Prints `SELF-TEST OK: ensure_adb_test.sh` on success.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$(cd "$here/../.." && pwd)/tool/ci/ensure_adb.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
rc=0

# Stub `sleep` records the requested backoff instead of waiting.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/sleep" <<'SH'
#!/usr/bin/env bash
echo "$1" >>"$SLEEP_LOG"
SH
chmod +x "$tmp/bin/sleep"

# fake_sdk <dir> <adb: exec|noexec|none> <sdkmanager: repair|fail|noop|none>
fake_sdk() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/platform-tools" "$d/cmdline-tools/latest/bin"
  case "$2" in
    exec) printf '#!/bin/sh\n' >"$d/platform-tools/adb"; chmod +x "$d/platform-tools/adb" ;;
    noexec) printf '#!/bin/sh\n' >"$d/platform-tools/adb"; chmod -x "$d/platform-tools/adb" ;;
    none) : ;;
  esac
  local sm="$d/cmdline-tools/latest/bin/sdkmanager"
  case "$3" in
    repair) cat >"$sm" <<'SH' ;;
#!/usr/bin/env bash
echo "$*" >>"$SDKM_LOG"
root="$(cd "$(dirname "$0")/../../.." && pwd)"
mkdir -p "$root/platform-tools"; printf '#!/bin/sh\n' >"$root/platform-tools/adb"; chmod +x "$root/platform-tools/adb"
SH
    fail) printf '#!/usr/bin/env bash\necho "$*" >>"$SDKM_LOG"\necho "Failed to install" >&2\nexit 1\n' >"$sm" ;;
    noop) printf '#!/usr/bin/env bash\necho "$*" >>"$SDKM_LOG"\nexit 0\n' >"$sm" ;;
    none) rm -f "$sm" ;;
  esac
  [ -f "$sm" ] && chmod +x "$sm"
  return 0
}

# check <name> <want rc> <want sdkmanager calls> <want stdout regex|""> <env...>
check() {
  local name="$1" want="$2" calls="$3" msg="$4" out got=0 n; shift 4
  : >"$tmp/sdkm.log"; : >"$tmp/sleep.log"
  out="$(env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" SDKM_LOG="$tmp/sdkm.log" SLEEP_LOG="$tmp/sleep.log" \
    "$@" timeout --signal=KILL 60 bash "$script" 2>&1)" || got=$?
  n="$(wc -l <"$tmp/sdkm.log" | tr -d ' ')"
  if [ "$got" -eq "$want" ] && [ "$n" = "$calls" ] && { [ -z "$msg" ] || grep -qE "$msg" <<<"$out"; }; then
    printf '  PASS  %s\n' "$name"
  else
    printf '  FAIL  %s (want rc=%s calls=%s /%s/, got rc=%s calls=%s: %s)\n' "$name" "$want" "$calls" "$msg" "$got" "$n" "$out"
    rc=1
  fi
}

echo "ensure_adb_test"
sdk="$tmp/sdk"

fake_sdk "$sdk" exec fail
check "adb present -> 0, no-op (sdkmanager never called)" 0 0 "" ANDROID_HOME="$sdk"
[ -x "$sdk/platform-tools/adb" ] && echo "  PASS  adb present -> platform-tools left untouched" || { echo "  FAIL  no-op removed adb"; rc=1; }
fake_sdk "$sdk" exec fail
check "adb present via ANDROID_SDK_ROOT -> 0, no-op" 0 0 "" ANDROID_SDK_ROOT="$sdk"

fake_sdk "$sdk" none repair
check "adb missing + repair works -> 0, one reinstall" 0 1 "platform-tools reinstalled \(attempt 1/3\)" ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=github-hosted
[ -x "$sdk/platform-tools/adb" ] && echo "  PASS  repaired adb is executable" || { echo "  FAIL  repaired adb missing"; rc=1; }
grep -qx -- '--install platform-tools' "$tmp/sdkm.log" && echo "  PASS  reinstall asks for platform-tools" || { echo "  FAIL  sdkmanager args ($(cat "$tmp/sdkm.log"))"; rc=1; }
fake_sdk "$sdk" noexec repair
check "adb present but not executable -> repaired, 0" 0 1 "adb missing at" ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=github-hosted

fake_sdk "$sdk" none fail
check "adb missing + repair fails -> 1 after 3 tries, ::error::" 1 3 "::error::adb missing: platform-tools reinstall failed 3x" ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=github-hosted
total="$(awk '{s+=$1} END {print s+0}' "$tmp/sleep.log")"
if [ "$total" -le 120 ] && [ "$(wc -l <"$tmp/sleep.log" | tr -d ' ')" = 2 ]; then
  echo "  PASS  repair fails -> total backoff ${total}s (< 2 min), no sleep after the last try"
else echo "  FAIL  backoff total=$total ($(tr '\n' ' ' <"$tmp/sleep.log"))"; rc=1; fi
grep -q '::group::sdkmanager log' <<<"$(fake_sdk "$sdk" none fail; env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" SDKM_LOG=/dev/null SLEEP_LOG=/dev/null ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=github-hosted bash "$script" 2>&1 || true)" \
  && echo "  PASS  repair fails -> sdkmanager log tail is printed" || { echo "  FAIL  no log tail"; rc=1; }
fake_sdk "$sdk" none noop
check "sdkmanager exits 0 but adb still missing -> 1" 1 3 "::error::adb missing" ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=github-hosted
fake_sdk "$sdk" none none
check "adb + sdkmanager missing -> 1 fast" 1 0 "::error::adb missing and sdkmanager not found" ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=github-hosted
check "no ANDROID_HOME / ANDROID_SDK_ROOT -> 1" 1 0 "::error::adb missing: neither ANDROID_HOME"

# Self-hosted (shared SDK): never delete platform-tools, never reinstall, fail fast.
for env_case in "RUNNER_ENVIRONMENT=self-hosted" "RUNNER_ENVIRONMENT="; do
  fake_sdk "$sdk" noexec repair
  check "adb broken on '$env_case' -> 1 fast, no reinstall" 1 0 "::error::adb missing at .* non-GitHub-hosted runner" ANDROID_HOME="$sdk" "$env_case"
  [ -f "$sdk/platform-tools/adb" ] && echo "  PASS  '$env_case' -> platform-tools left untouched (no rm -rf)" || { echo "  FAIL  '$env_case' deleted platform-tools"; rc=1; }
done
fake_sdk "$sdk" none repair
check "adb missing, RUNNER_ENVIRONMENT unset -> 1 fast, no reinstall" 1 0 "::error::adb missing" ANDROID_HOME="$sdk"
fake_sdk "$sdk" exec fail
check "adb present on self-hosted -> 0, no-op" 0 0 "" ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=self-hosted

# Real wall clock with the default backoff stays well inside the 2-min budget.
fake_sdk "$sdk" none fail
start="$(date +%s)"
env -i PATH="/usr/bin:/bin" HOME="$tmp/home" SDKM_LOG=/dev/null ANDROID_HOME="$sdk" RUNNER_ENVIRONMENT=github-hosted ENSURE_ADB_BACKOFF=1 \
  timeout --signal=KILL 120 bash "$script" >/dev/null 2>&1 && got=0 || got=$?
el=$(( $(date +%s) - start ))
if [ "$got" -eq 1 ] && [ "$el" -lt 120 ]; then echo "  PASS  repair fails -> exit 1 in ${el}s (real sleep, backoff 1)"
else echo "  FAIL  real run rc=$got in ${el}s"; rc=1; fi

if [ "$rc" -eq 0 ]; then echo "SELF-TEST OK: ensure_adb_test.sh"; else echo "SELF-TEST FAILED: ensure_adb_test.sh"; fi
exit "$rc"
