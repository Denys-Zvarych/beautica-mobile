// test/core/app_start_time_test.dart
//
// Unit tests for AppStartTime.
//
// These tests protect the MEDIUM-1 invariant established in the Phase 2.15
// splash-screen fix cycle: [AppStartTime.minSplashDuration] is the *single*
// source of truth for the 950 ms minimum splash duration. Both
// [auth_redirect.dart] and [splash_screen.dart] derive their timer constants
// from this field — if it changes, both consumers change atomically.
//
// [AppStartTime.resetForTest] is called in setUp/tearDown to make the tests
// independent of execution order (AppStartTime._start is a static field that
// persists across tests in the same isolate).

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AppStartTime.resetForTest);
  tearDown(AppStartTime.resetForTest);

  group('AppStartTime', () {
    test('minSplashDuration is 950 ms — single source of truth invariant', () {
      // This assertion is the MEDIUM-1 guard. If the 950 ms constant is
      // ever changed in AppStartTime, this test fails, forcing the author
      // to also update the splash gate documentation and confirm the change
      // is intentional. The test is intentionally fragile in that direction.
      expect(
        AppStartTime.minSplashDuration,
        equals(const Duration(milliseconds: 950)),
        reason:
            'splash_screen.dart and auth_redirect.dart both derive their '
            'timer constants from this field. A change here propagates '
            'atomically — that is the single-source-of-truth invariant.',
      );
    });

    test('elapsed() returns Duration.zero before record() is called', () {
      // _start is null after resetForTest — the defensive fallback must
      // return Duration.zero, not throw.
      expect(AppStartTime.elapsed(), equals(Duration.zero));
    });

    test(
      'elapsed() returns a positive duration after record() is called',
      () async {
        AppStartTime.record();
        // Yield for at least one microsecond.
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(
          AppStartTime.elapsed(),
          greaterThan(Duration.zero),
          reason: 'Clock must be running after record() is called.',
        );
      },
    );

    test(
      'record() is idempotent — second call does not reset the start time',
      () async {
        AppStartTime.record();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final firstElapsed = AppStartTime.elapsed();

        // Second call — must be a no-op (the ?? assignment in record() ensures
        // _start is only set if null).
        AppStartTime.record();
        final secondElapsed = AppStartTime.elapsed();

        // Time only moves forward. If record() reset _start, secondElapsed
        // would be near-zero.
        expect(
          secondElapsed,
          greaterThanOrEqualTo(firstElapsed),
          reason:
              'record() must not reset _start on subsequent calls — '
              'hot-restart cycles in debug mode must not corrupt the '
              'splash gate.',
        );
      },
    );

    test('elapsed() grows over time', () async {
      AppStartTime.record();
      final before = AppStartTime.elapsed();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final after = AppStartTime.elapsed();
      expect(after, greaterThan(before));
    });
  });
}
