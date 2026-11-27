#!/usr/bin/env bash
# Pre-emulator-launch guard (android-emulator-runner `pre-emulator-launch-script`):
# runs AFTER the action's own `sdkmanager --install platform-tools`, BEFORE the
# emulator starts. If that install left platform-tools without an executable adb,
# the action polls `adb` until emulator-boot-timeout and then cannot kill the
# emulator, so the step idles to its 35-min cap — on every attempt (run
# 45997515517, shard 4). Repairs the install (3 tries) or fails the attempt fast.
# Repairs ONLY on a GitHub-hosted runner (RUNNER_ENVIRONMENT=github-hosted): a
# self-hosted SDK may be shared, and deleting platform-tools there could break a
# concurrent job, so self-hosted (or unset) fails fast with no deletion.
# ENSURE_ADB_BACKOFF: seconds per retry step (default 10; tests set 0).
# why: docs/ci/emulator-integration.md#adb-missing
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$sdk_root" ] || { echo "::error::adb missing: neither ANDROID_HOME nor ANDROID_SDK_ROOT is set"; exit 1; }
adb="$sdk_root/platform-tools/adb"
sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
backoff="${ENSURE_ADB_BACKOFF:-10}"
[ -x "$adb" ] && exit 0
if [ "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]; then
  echo "::error::adb missing at '$adb' on a non-GitHub-hosted runner (RUNNER_ENVIRONMENT='${RUNNER_ENVIRONMENT:-}'); not repairing a possibly shared SDK — fix platform-tools on the runner"
  exit 1
fi
echo "::warning::adb missing at '$adb' after the action's SDK install; reinstalling platform-tools"
[ -x "$sdkmanager" ] || { echo "::error::adb missing and sdkmanager not found at '$sdkmanager'"; exit 1; }
log="$(mktemp)"
for attempt in 1 2 3; do
  rm -rf "$sdk_root/.temp" "$HOME/.android/cache" "$sdk_root/platform-tools"
  if "$sdkmanager" --install platform-tools < <(yes 2>/dev/null) > "$log" 2>&1 && [ -x "$adb" ]; then
    echo "platform-tools reinstalled (attempt $attempt/3)"
    rm -f "$log"
    exit 0
  fi
  echo "::group::sdkmanager log, attempt $attempt/3 (tail 40)"; tail -n 40 "$log"; echo "::endgroup::"
  if [ "$attempt" -lt 3 ]; then sleep $((attempt * backoff)); fi
done
rm -f "$log"
echo "::error::adb missing: platform-tools reinstall failed 3x; adb still missing at '$adb'"
exit 1
