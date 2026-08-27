// SECURITY / PRODUCT STRUCTURAL GUARD — the 2026-08-20 "screenshots are allowed"
// decision in `ScreenProtectionManager`.
//
// THIS FILE WAS REVERSED ON 2026-08-20. READ THIS BEFORE "FIXING" IT.
// --------------------------------------------------------------------
// It used to pin the OPPOSITE contract (SEC MEDIUM-2, 2026-07-29): that
// `_disable()` kept an `if (defaultTargetPlatform != TargetPlatform.android)`
// exemption around `preventScreenshotOff()`, because `MainActivity.onCreate` set
// `FLAG_SECURE` app-wide and this manager must never clear a baseline it did not
// set. That premise is GONE: `MainActivity` no longer sets FLAG_SECURE at all.
//
// WHY. The FLAG_SECURE baseline and both SEC MEDIUM findings were AUDIT-DRIVEN
// (MASVS-PLATFORM MS6 / mobile-security MS-4), never product decisions, and the
// product cost was never weighed. Beautica is a beauty discovery/booking
// marketplace — sharing what you found IS the growth loop, and capture-blocking
// stopped a user screenshotting their own booking confirmation, sharing a
// master's profile or a result photo, saving a price list, attaching a
// screenshot to support, or casting. The user weighed it on 2026-08-20 and chose
// sharing. Retained mitigation: the task-switcher thumbnail stays blank —
// natively on Android (`Activity.setRecentsScreenshotEnabled(false)` in
// `MainActivity`, API 33+, guarded because minSdk is 26) and here on iOS via
// `protectDataLeakageWithBlur`.
//
// WHAT THIS GUARD NOW LOCKS OUT: someone — most likely a future `mobile-security`
// pass re-filing MS6 — re-landing `preventScreenshotOn` / `preventScreenshotOff`
// in `lib/`, quietly restoring app-wide capture-blocking. That is WON'T FIX by
// product decision; this file is what turns it into a red test instead of a
// silent regression.
//
// WHY STRUCTURAL AND NOT BEHAVIOURAL (unchanged reasoning). The native calls are
// unreachable from any widget test: `_enable()`/`_disable()` return on their
// first line under `kDebugMode`, and `flutter test` always runs debug; and
// `ScreenProtector` is called STATICALLY, so there is no seam to fake. Making it
// behaviourally testable would need two production seams in a security-critical
// file, one of which would ship a way to defeat the debug short-circuit. A source
// assertion is the cheaper, safer guard.
//
// The 9 behavioural tests in `screen_protection_test.dart` prove the REFCOUNT
// contract and nothing about platform calls — they stay green either way, which
// is precisely why this tripwire has to exist.
//
// WHAT THIS TEST CANNOT DO. It asserts SHAPE, not behaviour, and it says nothing
// about `MainActivity.kt` — Kotlin is invisible to `flutter test`. The Android
// side needs a device/emulator check.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _sourcePath = 'lib/core/security/screen_protection.dart';

/// Strips `//` line comments and `/* … */` block comments.
///
/// MANDATORY before any structural assertion here: this file DOCUMENTS the very
/// call names being asserted on ("re-landing `preventScreenshotOn` …"). Matching
/// against raw source would count the prose and make every assertion below
/// meaningless.
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
/// matched by brace counting.
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
  late String enableBody;
  late String disableBody;

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

    final int enableAt = source.indexOf('void _enable()');
    expect(
      enableAt,
      isNot(-1),
      reason: 'ScreenProtectionManager._enable() must still exist',
    );
    enableBody = _bodyAt(source, enableAt);

    final int disableAt = source.indexOf('void _disable()');
    expect(
      disableAt,
      isNot(-1),
      reason: 'ScreenProtectionManager._disable() must still exist',
    );
    disableBody = _bodyAt(source, disableAt);
  });

  group('screenshots stay ALLOWED (product decision 2026-08-20)', () {
    test('_enable() does NOT turn screenshot blocking on', () {
      expect(
        enableBody.contains('preventScreenshotOn'),
        isFalse,
        reason:
            'ScreenProtector.preventScreenshotOn() is FLAG_SECURE on Android and '
            'a capture block on iOS. Re-adding it re-blocks the user from '
            "screenshotting their own booking, sharing a master's profile, or "
            'casting — reversed by explicit user decision on 2026-08-20. This is '
            'WON\'T FIX for MASVS-PLATFORM MS6 / MS-4; raise it as a product '
            'question, do not re-land it here.',
      );
    });

    test('_enable() DOES keep the app-switcher blur (retained mitigation)', () {
      expect(
        enableBody.contains('ScreenProtector.protectDataLeakageWithBlur()'),
        isTrue,
        reason:
            'the iOS app-switcher snapshot blur is the iOS half of "keep Recents '
            'blank" — the ONE mitigation the user kept. Removing it drops iOS '
            'below the Android behaviour (setRecentsScreenshotEnabled(false)).',
      );
    });

    test('_disable() is SYMMETRIC — no Android platform exemption', () {
      expect(
        disableBody.contains('TargetPlatform.android'),
        isFalse,
        reason:
            'the old Android teardown exemption existed only because '
            'MainActivity set an app-wide FLAG_SECURE baseline this manager must '
            'never clear. MainActivity no longer sets it, so there is nothing to '
            'exempt. A platform branch reappearing here means the FLAG_SECURE '
            'baseline came back.',
      );
      expect(
        disableBody.contains('ScreenProtector.protectDataLeakageWithBlurOff()'),
        isTrue,
        reason: 'the blur must still be torn down on the 1→0 release',
      );
    });

    test('_disable() does NOT call preventScreenshotOff', () {
      expect(
        disableBody.contains('preventScreenshotOff'),
        isFalse,
        reason:
            'this manager never turns capture-blocking ON, so it has nothing to '
            'turn OFF. A teardown call here implies a matching enable landed '
            'somewhere.',
      );
    });

    test('the reversal carries a comment explaining WHY', () {
      expect(
        rawSource.contains('PRODUCT DECISION 2026-08-20'),
        isTrue,
        reason:
            'a bare no-op manager reads like a bug to anyone who has not read '
            'the decision — the next security audit will file MS6 against it and '
            'someone will re-land FLAG_SECURE. The rationale must travel with '
            'the code.',
      );
    });
  });

  group('repository-wide', () {
    test(
      'NO file in lib/ calls preventScreenshotOn or preventScreenshotOff',
      () {
        final List<File> dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart'))
            .toList(growable: false);

        final Map<String, int> hits = <String, int>{};
        for (final File f in dartFiles) {
          final String stripped = _stripComments(f.readAsStringSync());
          final int n =
              'ScreenProtector.preventScreenshotOn('
                  .allMatches(stripped)
                  .length +
              'ScreenProtector.preventScreenshotOff('
                  .allMatches(stripped)
                  .length;
          if (n > 0) hits[f.path] = n;
        }

        expect(
          hits,
          isEmpty,
          reason:
              'app-wide AND per-screen capture-blocking are both out by product '
              'decision (2026-08-20). Any caller anywhere in lib/ re-opens it.',
        );
      },
    );
  });
}
