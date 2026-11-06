#!/usr/bin/env bash
# Pre-builds the debug integration APK for <entry.dart> ONCE, before the
# emulator attempts (mobile-perf audit cycle 2, P2). run_it_attempt.sh's
# `timeout` bound then covers the tests, not a cold Gradle/APK build.
#
#   prebuild_it_apk.sh <entry.dart>
#
# env: FLUTTER (flutter binary, default `flutter`).
#
# `flutter test` cannot take a pre-built binary, so each attempt still asks
# Gradle for the APK. The build below uses the inputs that `flutter test
# <entry>` uses on the x86_64 CI emulator -- debug mode, the default flavor
# (staging), the ABSOLUTE entry path as the target (flutter test passes
# `path.absolute`), target platform android-x64 (AndroidDevice.startApp builds
# ONLY the device ABI) and the define flutter test adds for integration runs
# (commands/test.dart: INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false).
# EXACT parity is impossible (PR #137 decision): getBuildInfo
# (runner/flutter_command.dart) appends FLUTTER_APP_FLAVOR, the FLUTTER_VERSION
# family and the feature-flag define AFTER every user define and refuses a
# user-set copy of them, while flutter test appends its define LAST -- so the
# `-Pdart-defines` order always differs and compileFlutterBuildDebug (kernel)
# re-runs each attempt. That costs nothing extra: on PR #137 attempts 2 and 3,
# whose inputs equal attempt 1's exactly, `assembleStagingDebug` still took
# 52-54 s, the same as attempt 1 after this pre-build (128 s cold). What the
# pre-build keeps OUT of the attempt bound is the cold part (dependency
# download, plugin/Kotlin compile, resource merge); the ~1 min warm rebuild
# (plus JVM start: the CI legs run Gradle daemon-less) stays inside it.
#
# Two tries: a dependency download can fail mid-build (the attempts used to
# retry the build implicitly). A missing / symlinked entry fails at once.
set -uo pipefail
entry="${1:?entry}"
flutter_bin="${FLUTTER:-flutter}"
if [ -L "$entry" ] || [ ! -f "$entry" ] || [ ! -s "$entry" ]; then
  echo "::error::prebuild: '$entry' is not a regular non-empty file"
  exit 1
fi
target="$(cd -P "$(dirname "$entry")" && pwd -P)/$(basename "$entry")"
for try in 1 2; do
  if "$flutter_bin" build apk --debug --target-platform android-x64 \
    -t "$target" \
    --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false; then
    echo "prebuild: debug APK for $target built (try $try)."
    exit 0
  fi
  echo "::warning::prebuild: try $try of 2 failed for $target"
done
echo "::error::prebuild: the debug APK for $target did not build (2 tries); the attempts are skipped."
exit 1
