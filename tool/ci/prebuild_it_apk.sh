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
# Gradle for the APK. The build below uses exactly the inputs that
# `flutter test <entry>` uses on the x86_64 CI emulator -- debug mode, the
# default flavor, the ABSOLUTE entry path as the target (flutter test passes
# `path.absolute`), target platform android-x64 and the one define flutter
# test adds for integration runs (commands/test.dart:
# INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false) -- so the attempt
# is a WARM INCREMENTAL build, not a cold one. NOT up to date: `flutter build`
# puts the user define first and `flutter test` appends its own last, so
# `-Pdart-defines` differs and compileFlutterBuildDebug (kernel) re-runs each
# attempt: a Dart recompile + repack, ~1-2 min, counted INSIDE the attempt
# bound (cold Gradle/dependency work stays out of it).
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
