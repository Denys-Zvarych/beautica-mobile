// Phase 17.2 — META-TEST for the overflow guard harness itself.
//
// WHY THIS FILE EXISTS
// --------------------
// `overflow_guard_stress_test.dart` proves the named screens DON'T overflow —
// every one of its 36 cases is green precisely because nothing overflows. That
// proves the *passing* path of the guard. It says nothing about whether the
// guard would actually CATCH an overflow if one were reintroduced. If the
// recorder silently stopped intercepting (exactly the bug this meta-test caught
// during QA: `flutter_test` reassigns `FlutterError.onError` per test, so a
// one-shot install was bypassed and EVERY stress test was a false-green), the
// stress suite would stay green and the regression would ship unnoticed.
//
// This file proves the guard's *failing* path: it deliberately builds an
// over-wide Row at a narrow width through the REAL `pumpApp` harness path and
// asserts the recorder CAPTURED the overflow. It also proves idempotence,
// per-test re-wrap, and that non-overflow framework errors are forwarded to the
// delegate (not swallowed).
//
// MECHANISM (why we don't rely on a real tearDown failure)
// --------------------------------------------------------
// `installOverflowGuard` (used by pumpApp) arms a `tearDown` that calls
// `fail(...)` when an overflow was recorded — but a test cannot cleanly assert
// on its OWN tearDown firing. So these meta-tests assert on the RECORDER state
// (`recordedOverflow`) directly, then `resetOverflowGuard()` so the deliberate
// overflow does not leak into a neighbour. Pumps use a SINGLE `pump()` (never
// `pumpAndSettle`): an overflow re-reports each frame, so settling a genuinely
// overflowing tree would hang — exactly why the guard records-then-fails rather
// than throwing inline.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overflow_guard.dart';
import 'pump_app.dart';

/// An over-wide Row that cannot fit at a phone width — guaranteed to emit
/// "A RenderFlex overflowed by N pixels on the right." when laid out at 320 dp.
Widget _guaranteedOverflow() => const Scaffold(
  body: Row(
    children: <Widget>[SizedBox(width: 5000, child: Text('over-wide'))],
  ),
);

void main() {
  // Each test clears the recording window before and after so a deliberate
  // overflow never bleeds into a neighbour under random ordering.
  setUp(resetOverflowGuard);
  tearDown(resetOverflowGuard);

  group('overflow guard — failing path (the durable proof)', () {
    testWidgets('the guard CAPTURES a deliberate overflow pumped via pumpApp', (
      tester,
    ) async {
      // Sanity: clean window before we overflow anything.
      expect(recordedOverflow, isNull, reason: 'window should start clean');

      // Drive a layout the framework cannot fit at 320 dp through the SAME
      // harness path real widget tests use (pumpApp installs the guard +
      // applies the width knob). A single pump lays it out once; the recorder
      // fires from FlutterError.onError during that layout flush.
      await tester.pumpApp(_guaranteedOverflow(), width: 320);
      await tester.pump();

      final FlutterErrorDetails? captured = recordedOverflow;
      expect(
        captured,
        isNotNull,
        reason:
            'the guard MUST record a deliberate overflow — if this is null the '
            'harness no longer intercepts during tests and every stress test '
            'is a false-green',
      );
      expect(
        captured!.exceptionAsString(),
        contains('overflowed'),
        reason: 'the captured details must be the RenderFlex overflow',
      );

      // Drain the framework-pending overflow so flutter_test does not ALSO fail
      // this meta-test on the (intentional) overflow it reported.
      tester.takeException();
      // Clear the recording window so pumpApp's armed tearDown does not fire on
      // this deliberate overflow.
      resetOverflowGuard();
    });

    testWidgets('only the FIRST overflow is retained (record-once)', (
      tester,
    ) async {
      await tester.pumpApp(_guaranteedOverflow(), width: 320);
      await tester.pump();
      final FlutterErrorDetails? first = recordedOverflow;
      expect(first, isNotNull);

      // Re-pump an over-wide tree. The recorder uses `??=`, so the FIRST
      // captured details must be retained (identity-stable), not replaced.
      await tester.pumpApp(_guaranteedOverflow(), width: 320);
      await tester.pump();
      expect(
        identical(recordedOverflow, first),
        isTrue,
        reason: 'recorder keeps the first overflow, ignores subsequent ones',
      );

      tester.takeException();
      resetOverflowGuard();
    });
  });

  group('overflow guard — passing path & delegation', () {
    testWidgets('a clean layout records NO overflow', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: Center(child: Text('fits fine'))),
        width: 320,
      );
      await tester.pump();
      expect(
        recordedOverflow,
        isNull,
        reason: 'a layout that fits must not be recorded as an overflow',
      );
    });

    test('installOverflowRecorder re-wraps a foreign handler then no-ops', () {
      // Arrange: a foreign handler (mimics flutter_test's per-test reporter that
      // is installed AFTER the suite-wide recorder).
      final FlutterExceptionHandler? original = FlutterError.onError;
      addTearDown(() => FlutterError.onError = original);

      var foreignCalls = 0;
      void foreign(FlutterErrorDetails _) => foreignCalls += 1;
      FlutterError.onError = foreign;
      resetInstalledSentinelForTest();

      // Act: install over the foreign handler. The live handler must now be OUR
      // recorder (re-wrapped), not the foreign one.
      installOverflowRecorder();
      expect(
        identical(FlutterError.onError, foreign),
        isFalse,
        reason: 'install must re-wrap a foreign handler, not leave it in place',
      );
      final FlutterExceptionHandler wrapped = FlutterError.onError!;

      // Re-installing while OUR recorder is live is a no-op (idempotent).
      installOverflowRecorder();
      installOverflowRecorder();
      expect(
        identical(FlutterError.onError, wrapped),
        isTrue,
        reason: 'repeated installs over our own recorder must be no-ops',
      );

      // The wrapped chain still forwards a non-overflow error to the foreign
      // delegate (nothing swallowed).
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('plain'),
          library: 'overflow_guard_meta_test',
        ),
      );
      expect(
        foreignCalls,
        1,
        reason: 'non-overflow error reaches the delegate',
      );
    });

    test(
      'non-overflow errors are forwarded to the delegate, not swallowed',
      () {
        final FlutterExceptionHandler? original = FlutterError.onError;
        addTearDown(() => FlutterError.onError = original);

        var forwarded = 0;
        FlutterErrorDetails? lastForwarded;
        FlutterError.onError = (FlutterErrorDetails details) {
          forwarded += 1;
          lastForwarded = details;
        };
        resetInstalledSentinelForTest();
        installOverflowRecorder();

        final FlutterErrorDetails plain = FlutterErrorDetails(
          exception: StateError('not a layout overflow'),
          library: 'overflow_guard_meta_test',
        );
        FlutterError.onError!(plain);

        expect(
          forwarded,
          1,
          reason: 'non-overflow error must reach the delegate',
        );
        expect(identical(lastForwarded, plain), isTrue);
        expect(
          recordedOverflow,
          isNull,
          reason: 'a non-overflow error must never be recorded as an overflow',
        );
      },
    );
  });
}
