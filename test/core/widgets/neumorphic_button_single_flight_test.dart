// `onPressedAsync` single-flight contract for the shared CTAs:
// NeumorphicButton, DestructiveButton, and the BookingCtaFooter pass-through.
//
// Taps are fired WITHOUT a pump between them. A pump would let the
// after-rebuild disable (`loading: true` / null onPressed) take effect and
// hide exactly the same-frame re-tap these buttons must now absorb.
//
// Anti-vacuity: drop the `if (_busy) return;` line in `_fire` and the
// "3 taps -> 1 call" rows go RED with 3 calls (verified when written).

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_cta_footer.dart';
import 'package:beautica_mobile/shared/widgets/destructive_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

Future<void> _tap3(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.tap(f);
  await tester.tap(f);
}

Finder _spinnerIn(Key key) => find.descendant(
  of: find.byKey(key),
  matching: find.byType(CircularProgressIndicator),
);

void main() {
  const Key k = Key('cta');

  group('NeumorphicButton.onPressedAsync', () {
    testWidgets('3 taps with no pump between -> exactly 1 call; spinner while '
        'busy; re-enabled after completion', (tester) async {
      int calls = 0;
      Completer<void> gate = Completer<void>();
      await _pump(
        tester,
        NeumorphicButton(
          key: k,
          label: 'Go',
          onPressed: null,
          onPressedAsync: () {
            calls++;
            return gate.future;
          },
        ),
      );

      await _tap3(tester, find.byKey(k));
      expect(calls, 1);

      await tester.pump();
      expect(_spinnerIn(k), findsOneWidget);
      await tester.tap(find.byKey(k), warnIfMissed: false);
      expect(calls, 1, reason: 'busy: a tap after the rebuild is ignored too');

      gate.complete();
      await tester.pump();
      expect(_spinnerIn(k), findsNothing);

      gate = Completer<void>();
      await tester.tap(find.byKey(k));
      expect(calls, 2, reason: 're-enabled once the future completed');
      gate.complete();
      await tester.pump();
    });

    testWidgets('re-enabled when the action throws', (tester) async {
      int calls = 0;
      await _pump(
        tester,
        NeumorphicButton(
          key: k,
          label: 'Go',
          onPressed: null,
          onPressedAsync: () async {
            calls++;
            throw StateError('boom');
          },
        ),
      );

      await tester.tap(find.byKey(k));
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
      await tester.tap(find.byKey(k));
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
      expect(calls, 2);
    });

    testWidgets('unmount while busy is safe', (tester) async {
      final Completer<void> gate = Completer<void>();
      await _pump(
        tester,
        NeumorphicButton(
          key: k,
          label: 'Go',
          onPressed: null,
          onPressedAsync: () => gate.future,
        ),
      );
      await tester.tap(find.byKey(k));
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('onPressedAsync null: onPressed keeps its old behaviour (no '
        'internal busy state)', (tester) async {
      int calls = 0;
      await _pump(
        tester,
        NeumorphicButton(key: k, label: 'Go', onPressed: () => calls++),
      );
      await _tap3(tester, find.byKey(k));
      await tester.pump();
      expect(calls, 3);
      expect(_spinnerIn(k), findsNothing);
    });

    // A plain `onPressed` must run SYNCHRONOUSLY from the gesture callback,
    // as before `onPressedAsync` existed: a sync throw is reported by the
    // gesture recognizer through FlutterError.onError (`takeException`), not
    // lost as an unhandled zone error from an un-awaited async wrapper.
    // Anti-vacuity: route the sync path back through `unawaited(_fire())` and
    // this goes RED (verified when written).
    testWidgets('onPressedAsync null: a sync-throwing onPressed is reported '
        'via FlutterError.onError, synchronously', (tester) async {
      await _pump(
        tester,
        NeumorphicButton(
          key: k,
          label: 'Go',
          onPressed: () => throw StateError('sync boom'),
        ),
      );
      await tester.tap(find.byKey(k));
      expect(tester.takeException(), isA<StateError>());
    });
  });

  group('DestructiveButton.onPressedAsync', () {
    testWidgets('3 taps with no pump between -> exactly 1 call; re-enabled '
        'after completion', (tester) async {
      int calls = 0;
      Completer<void> gate = Completer<void>();
      await _pump(
        tester,
        DestructiveButton(
          key: k,
          label: 'Delete',
          onPressed: null,
          onPressedAsync: () {
            calls++;
            return gate.future;
          },
        ),
      );

      await _tap3(tester, find.byKey(k));
      expect(calls, 1);
      await tester.pump();
      expect(_spinnerIn(k), findsOneWidget);

      gate.complete();
      await tester.pump();
      gate = Completer<void>();
      await tester.tap(find.byKey(k));
      expect(calls, 2);
      gate.complete();
      await tester.pump();
    });

    // Same contract as the NeumorphicButton row above (anti-vacuity likewise
    // verified when written).
    testWidgets('onPressedAsync null: a sync-throwing onPressed is reported '
        'via FlutterError.onError, synchronously', (tester) async {
      await _pump(
        tester,
        DestructiveButton(
          key: k,
          label: 'Delete',
          onPressed: () => throw StateError('sync boom'),
        ),
      );
      await tester.tap(find.byKey(k));
      expect(tester.takeException(), isA<StateError>());
    });
  });

  group('BookingCtaFooter.onPressedAsync', () {
    testWidgets('passes through: 3 taps -> 1 call', (tester) async {
      int calls = 0;
      final Completer<void> gate = Completer<void>();
      await _pump(
        tester,
        BookingCtaFooter(
          label: 'Book',
          enabled: true,
          loading: false,
          buttonKey: k,
          onPressedAsync: () {
            calls++;
            return gate.future;
          },
        ),
      );

      await _tap3(tester, find.byKey(k));
      expect(calls, 1);
      gate.complete();
      await tester.pump();
    });

    testWidgets('enabled: false gates onPressedAsync', (tester) async {
      int calls = 0;
      await _pump(
        tester,
        BookingCtaFooter(
          label: 'Book',
          enabled: false,
          loading: false,
          buttonKey: k,
          onPressedAsync: () async => calls++,
        ),
      );
      await tester.tap(find.byKey(k), warnIfMissed: false);
      expect(calls, 0);
    });
  });
}
