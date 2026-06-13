// Widget unit tests for AppRefreshIndicator.
//
// Covers:
//   1. Structural wrap — renders a Material [RefreshIndicator] around the child.
//   2. Brand colors — spinner color == BrandColors.accent;
//                     background == BrandColors.base.
//   3. Callback fired once — a pull-down fling triggers [onRefresh] exactly once
//      and the indicator dismisses after the future completes.
//   4. Short-content trigger — [onRefresh] fires even when the child's content
//      is shorter than the viewport (relies on [AlwaysScrollableScrollPhysics]
//      on the caller-supplied scroll view; the widget itself does not add it, but
//      the integration across the contract is exercised here via a single-item
//      list that underflows an 800-px viewport).
//
// Convention notes (mobile-qa):
//   • Finders use byKey / byType — never raw localised strings (M2).
//   • No `pumpAndSettle` while the refresh future is parked (would never settle
//     with an open Completer). Manual pump(Duration) is used instead with a
//     comment explaining why (M6 exception: determined by indicator animation).
//   • No `pump(Duration(seconds: n))` for timing — only for the indicator's own
//     250 ms dismiss animation after the future resolves. This is the
//     flutter/material RefreshIndicator's built-in duration, not a magic wait.
//   • `.withValues(alpha:)` is used (not `.withOpacity()`) per project style.

import 'dart:async';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps [AppRefreshIndicator] inside a plain MaterialApp. No ProviderScope
/// needed — the widget under test is stateless, pure Flutter Material.
Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  required Future<void> Function() onRefresh,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppRefreshIndicator(
          key: const Key('sut'),
          onRefresh: onRefresh,
          child: child,
        ),
      ),
    ),
  );
}

/// A minimal scrollable list with [AlwaysScrollableScrollPhysics] that is
/// SHORTER than the viewport (one item) so the pull gesture can still be
/// detected. Uses the physics the project's screens adopt.
Widget _shortScrollable() {
  return ListView(
    key: const Key('scroll-child'),
    physics: const AlwaysScrollableScrollPhysics(
      parent: BouncingScrollPhysics(),
    ),
    children: const <Widget>[
      SizedBox(key: Key('child-item'), height: 60, child: Text('Item')),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AppRefreshIndicator', () {
    // ── 1. Structural wrap ──────────────────────────────────────────────────
    testWidgets('renders a RefreshIndicator wrapping the given child', (
      tester,
    ) async {
      await _pump(tester, onRefresh: () async {}, child: _shortScrollable());

      expect(find.byType(RefreshIndicator), findsOneWidget);
      // The child scroll view is present inside the indicator.
      expect(find.byKey(const Key('scroll-child')), findsOneWidget);
    });

    // ── 2. Brand colors ─────────────────────────────────────────────────────
    testWidgets(
      'uses BrandColors.accent as spinner color and BrandColors.base as '
      'backgroundColor on the underlying RefreshIndicator',
      (tester) async {
        await _pump(tester, onRefresh: () async {}, child: _shortScrollable());

        final RefreshIndicator indicator = tester.widget<RefreshIndicator>(
          find.byType(RefreshIndicator),
        );

        expect(
          indicator.color,
          BrandColors.accent,
          reason: 'Spinner color must be BrandColors.accent (#B89A7A)',
        );
        expect(
          indicator.backgroundColor,
          BrandColors.base,
          reason:
              'Disc background must be BrandColors.base (#E6DDD0) — the '
              'neumorphic surface token',
        );
      },
    );

    // ── 3. Callback fires exactly once + indicator dismisses ────────────────
    //
    // Strategy:
    //   • Park [onRefresh] on a Completer so the indicator stays open.
    //   • Fling downward to trigger the pull gesture.
    //   • Pump one frame to start the indicator animation.
    //   • Complete the Completer — the spinner should now dismiss.
    //   • pump(Duration(milliseconds: 300)) advances past the built-in 250 ms
    //     dismiss animation of Material's RefreshIndicator. This is the only
    //     magic-number pump in this file; it is bounded by the Material library,
    //     not by application code.
    testWidgets(
      'a pull-down fling invokes onRefresh exactly once and the indicator '
      'dismisses after the future completes',
      (tester) async {
        var callCount = 0;
        final completer = Completer<void>();

        await _pump(
          tester,
          onRefresh: () {
            callCount++;
            return completer.future;
          },
          child: _shortScrollable(),
        );

        // Fling down from the top of the scrollable area to trigger the drag.
        await tester.fling(
          find.byKey(const Key('scroll-child')),
          const Offset(0, 400),
          800,
        );
        // Pump one frame: RefreshIndicator starts its pull animation.
        await tester.pump();
        // Pump past the indicator drag-reveal animation (200 ms).
        await tester.pump(const Duration(milliseconds: 200));

        // onRefresh must have been invoked exactly once at this point.
        expect(
          callCount,
          1,
          reason: 'onRefresh must be called exactly once per pull',
        );

        // Complete the refresh future → indicator enters dismiss phase.
        completer.complete();
        await tester.pump();
        // Advance past Material's 250 ms dismiss animation.
        await tester.pump(const Duration(milliseconds: 300));

        // The indicator circle is gone from the tree after dismissal.
        // (RefreshIndicatorState removes the overlay widget on completion.)
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'Spinner must dismiss after the refresh future completes',
        );

        // No extra calls.
        expect(callCount, 1);
      },
    );

    // ── 4. Short-content trigger ────────────────────────────────────────────
    //
    // A child that underflows the viewport can only be pulled if it has
    // AlwaysScrollableScrollPhysics. The project contract (documented in the
    // AppRefreshIndicator doc comment) requires callers to set this on their
    // scroll view. This test exercises that contract end-to-end: the pull must
    // fire onRefresh even with a very short list.
    testWidgets(
      'onRefresh fires when content is shorter than the viewport (underflow '
      'case — relies on caller-supplied AlwaysScrollableScrollPhysics)',
      (tester) async {
        var called = false;
        final completer = Completer<void>();

        await _pump(
          tester,
          onRefresh: () {
            called = true;
            return completer.future;
          },
          child: _shortScrollable(),
        );

        await tester.fling(
          find.byKey(const Key('scroll-child')),
          const Offset(0, 400),
          800,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          called,
          isTrue,
          reason:
              'onRefresh must fire on a short-content list with '
              'AlwaysScrollableScrollPhysics',
        );

        completer.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      },
    );

    // ── 5. Multiple children types accepted ────────────────────────────────
    testWidgets(
      'accepts any scrollable child — ListView.builder renders correctly',
      (tester) async {
        await _pump(
          tester,
          onRefresh: () async {},
          child: ListView.builder(
            key: const Key('builder-child'),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 3,
            itemBuilder: (_, i) => SizedBox(
              key: Key('item-$i'),
              height: 80,
              child: Text('Item $i'),
            ),
          ),
        );

        expect(find.byType(RefreshIndicator), findsOneWidget);
        expect(find.byKey(const Key('builder-child')), findsOneWidget);
      },
    );
  });
}
