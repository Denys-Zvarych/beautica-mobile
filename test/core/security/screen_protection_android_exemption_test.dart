// SECURITY STRUCTURAL GUARD — SEC MEDIUM-2, the Android FLAG_SECURE teardown
// exemption in `ScreenProtectionManager._disable()`.
//
// THE BUG THIS LOCKS OUT
// ----------------------
// `MainActivity.onCreate` sets Android `FLAG_SECURE` app-wide for every non-debug
// build, so this manager NEVER SETS the Android flag — and must therefore never
// CLEAR it. It used to. The first 1→0 release (open Settings, pop back) called
// `ScreenProtector.preventScreenshotOff()`, which cleared the Activity-level flag
// and left the process UNPROTECTED FOR ITS ENTIRE REMAINING LIFETIME. Everything
// typed afterwards — a searched client name, a booking — became capturable by any
// screen-recording app and was baked into the Recent Apps thumbnail.
//
// iOS has no such baseline, so it still gets the full teardown; and the
// app-switcher blur teardown is unconditional (a no-op on Android), which is
// what preserves iOS's exact acquire/release semantics.
//
// WHY THIS IS A SOURCE-STRUCTURAL TEST AND NOT A BEHAVIOURAL ONE
// --------------------------------------------------------------
// The fix is UNREACHABLE from any widget test, for two compounding reasons:
//
//   1. `_disable()` returns at its very first line on `kDebugMode`, and
//      `flutter test` ALWAYS runs in debug. Execution never reaches the platform
//      branch at all. `debugDefaultTargetPlatformOverride` does not help —
//      the function has already returned.
//   2. `ScreenProtector` is called STATICALLY (`ScreenProtector.preventScreen‐
//      shotOff()`), so there is no seam to substitute a fake through and no way
//      to observe whether the call happened.
//
// Making it behaviourally testable would require TWO new production seams in a
// security-critical file — an injectable ScreenProtector façade AND a way to
// defeat the `kDebugMode` short-circuit. Both would exist purely for the test,
// and the second would mean shipping a code path that can turn protection
// teardown on in release. That is a worse trade than a structural assertion, so
// production code is deliberately left UNCHANGED here.
//
// The consequence is important and is the reason this file exists: the 9
// behavioural tests in `screen_protection_test.dart` prove the REFCOUNT contract
// (0→1 enables, 1→0 disables, double-release is safe, reset is idempotent) and
// NOTHING about the platform exemption. Re-introducing symmetric teardown would
// restore the process-lifetime FLAG_SECURE leak with every one of them still
// green. This guard is what turns that silent regression into a failing test.
//
// Precedent: `test/build_guards/add_2_calendar_version_pin_test.dart` uses the
// same technique for the same reason — the real failure mode is invisible to the
// cheap CI gate, so a source assertion is the only affordable guard.
//
// WHAT THIS TEST CANNOT DO
// ------------------------
// It asserts SHAPE, not behaviour. It cannot prove the native call is skipped at
// runtime on Android; it proves the branch that skips it is present, encloses
// the right call, and does not enclose the wrong one. Treat it as a tripwire on
// a known regression, not as coverage of the platform channel.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _sourcePath = 'lib/core/security/screen_protection.dart';

/// The Android-exemption condition, verbatim.
const String _guardCondition =
    'if (defaultTargetPlatform != TargetPlatform.android) {';

/// Strips `//` line comments and `/* … */` block comments.
///
/// MANDATORY before any structural assertion here: this file DOCUMENTS the very
/// call names being asserted on ("…called `preventScreenshotOff()`, which
/// cleared the Activity-level flag…"). Matching against raw source would count
/// the prose and make every assertion below meaningless.
String _stripComments(String source) {
  final StringBuffer out = StringBuffer();
  bool inLine = false;
  bool inBlock = false;
  for (int i = 0; i < source.length; i++) {
    final String c = source[i];
    final String next = i + 1 < source.length ? source[i + 1] : '';
    if (inLine) {
      if (c == '\n') {
        inLine = false;
        out.write(c);
      }
      continue;
    }
    if (inBlock) {
      if (c == '*' && next == '/') {
        inBlock = false;
        i++;
      }
      continue;
    }
    if (c == '/' && next == '/') {
      inLine = true;
      i++;
      continue;
    }
    if (c == '/' && next == '*') {
      inBlock = true;
      i++;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

/// Returns the `{ … }` body that starts at the first `{` at or after [from],
/// matched by brace counting. String/comment aware enough for this file (which
/// contains no braces inside string literals).
String _bodyAt(String source, int from) {
  final int open = source.indexOf('{', from);
  expect(
    open,
    isNot(-1),
    reason: 'expected an opening brace after index $from',
  );
  int depth = 0;
  for (int i = open; i < source.length; i++) {
    final String c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  fail('unbalanced braces starting at index $open in $_sourcePath');
}

void main() {
  /// Raw file text — used ONLY by the "rationale comment survives" assertion.
  late String rawSource;

  /// Comment-stripped source — the basis for every structural assertion.
  late String source;
  late String disableBody;
  late String guardBody;

  /// Whether the Android-exemption branch was found at all.
  late bool guardPresent;

  /// `_disable()`'s body with the Android-exemption block removed — i.e. the
  /// statements that run on EVERY platform.
  late String unconditionalPart;

  setUpAll(() {
    final File file = File(_sourcePath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$_sourcePath is missing — if the manager moved, MOVE THIS GUARD WITH '
          'IT rather than deleting it',
    );
    rawSource = file.readAsStringSync();
    source = _stripComments(rawSource);

    final int disableAt = source.indexOf('void _disable()');
    expect(
      disableAt,
      isNot(-1),
      reason: 'ScreenProtectionManager._disable() must still exist',
    );
    disableBody = _bodyAt(source, disableAt);

    // Parsed WITHOUT asserting here: an `expect` in setUpAll reports as one
    // unnamed `(setUpAll)` failure, which hides WHICH contract broke. Presence
    // is asserted by its own named test below; this just degrades gracefully so
    // that test is the one that fails.
    final int guardAt = disableBody.indexOf(_guardCondition);
    guardPresent = guardAt != -1;
    guardBody = guardPresent ? _bodyAt(disableBody, guardAt) : '';
    unconditionalPart = guardPresent
        ? disableBody.replaceFirst(guardBody, '')
        : disableBody;
  });

  group('_disable() Android exemption', () {
    test('the Android-exemption branch exists at all', () {
      expect(
        guardPresent,
        isTrue,
        reason:
            'the Android exemption `$_guardCondition` is GONE from _disable(). '
            'Restoring symmetric teardown clears the app-wide FLAG_SECURE that '
            'MainActivity set and never restores it — the process stays '
            'screenshot-capturable for the rest of its life.',
      );
    });

    test('preventScreenshotOff is INSIDE the non-Android guard', () {
      expect(
        guardBody.contains('ScreenProtector.preventScreenshotOff()'),
        isTrue,
        reason:
            'the Android FLAG_SECURE teardown must be reachable only when the '
            'platform is NOT Android',
      );
    });

    test('preventScreenshotOff is NOT called unconditionally', () {
      expect(
        unconditionalPart.contains('ScreenProtector.preventScreenshotOff('),
        isFalse,
        reason:
            'a second, unguarded call would defeat the exemption entirely — '
            'this is the exact regression SEC MEDIUM-2 fixed',
      );
    });

    test('the iOS app-switcher blur teardown stays UNCONDITIONAL', () {
      expect(
        unconditionalPart.contains(
          'ScreenProtector.protectDataLeakageWithBlurOff()',
        ),
        isTrue,
        reason:
            'the blur teardown is a no-op on Android and iOS depends on it for '
            'exact acquire/release symmetry — moving it inside the platform '
            'guard would be a silent iOS behaviour change',
      );
      expect(
        guardBody.contains('protectDataLeakageWithBlurOff'),
        isFalse,
        reason: 'it must not ALSO be inside the guard',
      );
    });

    test('_enable() still turns Android protection ON unconditionally', () {
      // The asymmetry is the whole design: enable is symmetric across
      // platforms, disable is not. Pinning both halves stops someone
      // "restoring symmetry" in the wrong direction.
      final String enableBody = _bodyAt(
        source,
        source.indexOf('void _enable()'),
      );
      expect(
        enableBody.contains('ScreenProtector.preventScreenshotOn()'),
        isTrue,
      );
      expect(
        enableBody.contains('TargetPlatform.android'),
        isFalse,
        reason:
            'enabling is NOT platform-branched — only the teardown is exempt',
      );
    });

    test('the exemption carries a comment explaining WHY', () {
      expect(
        rawSource.contains('ANDROID IS DELIBERATELY EXEMPT'),
        isTrue,
        reason:
            'this branch looks like a bug to anyone who has not read the '
            'incident — the rationale must travel with the code, or the next '
            'reader will "simplify" it away',
      );
    });
  });

  group('repository-wide', () {
    test('preventScreenshotOff is called from exactly ONE place in lib/', () {
      final List<File> dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList(growable: false);

      final Map<String, int> hits = <String, int>{};
      for (final File f in dartFiles) {
        final int n = 'ScreenProtector.preventScreenshotOff('
            .allMatches(_stripComments(f.readAsStringSync()))
            .length;
        if (n > 0) hits[f.path] = n;
      }

      expect(
        hits,
        <String, int>{_sourcePath: 1},
        reason:
            'any OTHER caller re-opens the leak from a different file, where '
            'the guard above cannot see it',
      );
    });
  });
}
