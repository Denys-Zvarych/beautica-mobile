// BUILD-TOOLCHAIN GUARD — add_2_calendar version pin (upper-bounded to < 3.1.0).
//
// WHY THIS FILE EXISTS
// --------------------
// add_2_calendar 3.1.0 / 3.1.1 rewrote their shipped `android/build.gradle.kts`
// for the AGP-9 / Gradle-9 plugin-application flow. Those scripts use the
// Kotlin-Gradle-Plugin 2.3 DSL — `kotlin { compilerOptions { jvmTarget = … } }`
// and directories-based sourceSets. THIS project is on AGP 8.11.1 / Gradle 8.14
// / Kotlin 2.2.20, where that DSL does not resolve: Gradle script compilation
// dies with `Unresolved reference: compilerOptions` and the `assembleDebug`
// task aborts, so `flutter build apk` fails outright.
//
// THE REGRESSION THIS TEST GUARDS
// -------------------------------
// This class of breakage is INVISIBLE to the cheap CI gate. `flutter analyze`
// and every `flutter test` (unit + widget) exercise the Dart layer only — they
// never invoke the Android Gradle build, so a bad `add_2_calendar` upgrade
// passes analyze + the whole widget suite green and only explodes at APK
// assemble time (which CI does not run per-push). A pure source-structural
// pin-check is therefore the ONLY cheap guard: it runs in the unit job and
// fails BEFORE anyone reaches a broken build.
//
// The fix this test locks in: `pubspec.yaml` constrains the dependency to
// `">=3.0.1 <3.1.0"` (3.0.1 ships the conventional Groovy plugin build that is
// AGP-8 compatible), and `pubspec.lock` resolves `add_2_calendar 3.0.1`. The
// Dart API is unchanged across the 3.0.x → 3.1.x boundary
// (`Add2Calendar.addEvent2Cal(Event)`), so the downgrade is behaviourally inert.
//
// UNBLOCK CONDITION
// -----------------
// Bump the pin (and this guard's upper bound) to allow `>= 3.1.0` ONLY after the
// project's Android toolchain moves to AGP 9 / Gradle 9, at which point the
// plugin's KGP-2.3 build script resolves. Until then, keep the ceiling below
// 3.1.0.
//
// Self-contained on purpose: dart:io + flutter_test only, no pub_semver (which
// is transitive here) — the version math below is a tiny hand-rolled comparator
// so the guard adds no dependency surface.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The forbidden floor: first version shipping the AGP-9 build script.
const List<int> _blockedFrom = <int>[3, 1, 0];

/// The known-good minimum: 3.0.1 (last AGP-8-compatible Groovy build).
const List<int> _minAllowed = <int>[3, 0, 1];

/// Parses a bare `major.minor.patch` string into a 3-int list.
List<int> _parseVersion(String raw) {
  final RegExpMatch? m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(raw.trim());
  if (m == null) {
    throw FormatException('not a semantic version: "$raw"');
  }
  return <int>[
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  ];
}

/// Returns < 0, 0, or > 0 for a < b, a == b, a > b (lexicographic on triple).
int _compare(List<int> a, List<int> b) {
  for (int i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

void main() {
  group('add_2_calendar version pin (AGP-8 / Gradle-8 toolchain guard)', () {
    test('pubspec.yaml constrains add_2_calendar with an upper bound < 3.1.0', () {
      final File pubspec = File('pubspec.yaml');
      expect(pubspec.existsSync(), isTrue, reason: 'pubspec.yaml must exist');

      // Find the dependency declaration line, ignoring the `#`-comment block
      // above it. Matches `  add_2_calendar: <constraint>` at 2-space indent,
      // stripping surrounding quotes and any trailing inline comment.
      final RegExp depLine = RegExp(
        '''^\\s{2}add_2_calendar:\\s*["']?([^"'\\n#]+?)["']?\\s*(?:#.*)?\$''',
        multiLine: true,
      );
      final RegExpMatch? m = depLine.firstMatch(pubspec.readAsStringSync());
      expect(
        m,
        isNotNull,
        reason:
            'could not find an `add_2_calendar:` dependency line in pubspec.yaml',
      );

      final String constraint = m!.group(1)!.trim();

      // A caret (`^3.x`) constraint is unbounded within the major: it admits
      // everything up to < 4.0.0, hence >= 3.1.0 — reject it outright.
      expect(
        constraint.startsWith('^'),
        isFalse,
        reason:
            'pubspec.yaml `add_2_calendar: $constraint` is a caret constraint, '
            'which allows 3.1.0+ (the AGP-9 build). Use an explicit upper bound '
            '`<3.1.0` until the Android toolchain moves to AGP 9 / Gradle 9.',
      );

      // Require an explicit exclusive upper bound and check it does not admit
      // 3.1.0. For `<U`, version 3.1.0 is allowed iff 3.1.0 < U; so we demand
      // U <= 3.1.0. (`<3.1.0` passes; `<3.2.0` / no bound fail.)
      final RegExpMatch? upper = RegExp(
        r'<\s*(\d+\.\d+\.\d+)',
      ).firstMatch(constraint);
      expect(
        upper,
        isNotNull,
        reason:
            'pubspec.yaml `add_2_calendar: $constraint` has no `<x.y.z` upper '
            'bound — it may resolve to 3.1.0+ (the AGP-9 build that breaks '
            '`flutter build apk` on AGP 8.11.1 / Gradle 8.14).',
      );
      final List<int> upperBound = _parseVersion(upper!.group(1)!);
      expect(
        _compare(upperBound, _blockedFrom) <= 0,
        isTrue,
        reason:
            'pubspec.yaml `add_2_calendar: $constraint` upper bound '
            '${upperBound.join('.')} admits 3.1.0+, which ships the '
            'AGP-9/Gradle-9 build.gradle.kts and breaks the Android assemble. '
            'Keep the ceiling at `<3.1.0` until AGP 9 / Gradle 9.',
      );

      // The lower bound (if present) must still admit the known-good 3.0.1.
      final RegExpMatch? lower = RegExp(
        r'>=\s*(\d+\.\d+\.\d+)',
      ).firstMatch(constraint);
      if (lower != null) {
        final List<int> lowerBound = _parseVersion(lower.group(1)!);
        expect(
          _compare(lowerBound, _minAllowed) <= 0,
          isTrue,
          reason:
              'pubspec.yaml `add_2_calendar: $constraint` lower bound '
              '${lowerBound.join('.')} excludes the known-good 3.0.1 build.',
        );
      }
    });

    test('pubspec.lock resolves add_2_calendar to >= 3.0.1 and < 3.1.0', () {
      final File lock = File('pubspec.lock');
      expect(lock.existsSync(), isTrue, reason: 'pubspec.lock must exist');

      // Locate the `add_2_calendar:` package block, then its `version:` field.
      // The block is a top-level (2-space) key under `packages:`; the version
      // sits a few lines below at 4-space indent.
      final RegExp lockBlock = RegExp(
        '''^\\s{2}add_2_calendar:\\s*\$.*?^\\s{4}version:\\s*["']?([^"'\\n]+)["']?''',
        multiLine: true,
        dotAll: true,
      );
      final RegExpMatch? m = lockBlock.firstMatch(lock.readAsStringSync());
      expect(
        m,
        isNotNull,
        reason:
            'could not find the resolved add_2_calendar version in pubspec.lock',
      );

      final List<int> resolved = _parseVersion(m!.group(1)!);

      // The LOCKED version must sit in [3.0.1, 3.1.0).
      expect(
        _compare(resolved, _minAllowed) >= 0 &&
            _compare(resolved, _blockedFrom) < 0,
        isTrue,
        reason:
            'pubspec.lock resolves add_2_calendar ${resolved.join('.')}, '
            'outside the required [3.0.1, 3.1.0) window. 3.1.0+ ships the AGP-9 '
            'build script that fails `flutter build apk` on AGP 8.11.1 / '
            'Gradle 8.14 — a failure invisible to analyze + widget tests. '
            'Run `flutter pub get` after correcting the pubspec.yaml pin.',
      );
    });
  });
}
