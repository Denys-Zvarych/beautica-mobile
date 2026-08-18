// Phase 4.5 — Widget tests for the shared [RatingSummaryCard] header in
// isolation (the aggregate rating card atop both the salon profile and the
// master "Мої відгуки" screen).
//
// Contract pinned here:
//   • the big average renders under [averageKey], formatted to 1 decimal, or
//     «—» when avgRating is null (no reviews yet — safe if the summary endpoint
//     is briefly unavailable).
//   • the caller-provided countLabel renders verbatim.
//   • the 5★→1★ distribution counts all render (one row per star bucket).

import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _avgKey = Key('master-review-summary-average');

Widget _host(Widget card) => Scaffold(body: Center(child: card));

void main() {
  testWidgets('renders the average to one decimal under averageKey', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        const RatingSummaryCard(
          avgRating: 4.25,
          reviewCount: 3,
          distribution: <int>[1, 1, 1, 0, 0],
          countLabel: '3 відгуки',
          averageKey: _avgKey,
        ),
      ),
    );

    final Text avg = tester.widget<Text>(find.byKey(_avgKey));
    expect(avg.data, '4.3'); // toStringAsFixed(1) rounds 4.25 → 4.3
  });

  testWidgets('renders «—» when avgRating is null (zero reviews)', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        const RatingSummaryCard(
          avgRating: null,
          reviewCount: 0,
          distribution: <int>[0, 0, 0, 0, 0],
          countLabel: '0 відгуків',
          averageKey: _avgKey,
        ),
      ),
    );

    final Text avg = tester.widget<Text>(find.byKey(_avgKey));
    expect(avg.data, '—');
  });

  testWidgets('renders the caller-provided count label verbatim', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        const RatingSummaryCard(
          avgRating: 4.0,
          reviewCount: 128,
          distribution: <int>[100, 20, 5, 2, 1],
          countLabel: '128 відгуків',
          averageKey: _avgKey,
        ),
      ),
    );

    // i18n-finder-ok: countLabel is passed in already-localised by the caller; opaque data string, not UI copy.
    expect(find.text('128 відгуків'), findsOneWidget);
  });

  testWidgets('renders every 5★→1★ distribution bucket count', (tester) async {
    // Distinct counts that do NOT collide with the star-number labels (1..5).
    await tester.pumpApp(
      _host(
        const RatingSummaryCard(
          avgRating: 4.1,
          reviewCount: 63,
          distribution: <int>[12, 8, 30, 7, 6],
          countLabel: '63 відгуки',
          averageKey: _avgKey,
        ),
      ),
    );

    for (final String count in <String>['12', '8', '30', '7', '6']) {
      expect(
        find.text(count),
        findsOneWidget,
        reason: 'distribution bucket count "$count" must render exactly once',
      );
    }
  });

  // QA (mobile-qa golden-verdict follow-up, backlog row 313) — backlog row
  // 313 deferred a golden for "MyRatingScreen star-row at 320px/large text
  // scale... until the backend client-rating endpoint ships and the screen
  // stabilises". The endpoint has now shipped, but the screen ALSO gained a
  // whole new two-column layout (proportional bars + right-aligned counts)
  // that has NEVER been exercised at a stress size, AND a follow-up
  // (mobile-perf LOW) is about to strip this card's `HubFlatCard` wrapper at
  // its three call sites — a golden captured today would need re-baselining
  // the moment that lands, which is exactly the kind of self-referential
  // churn a golden should not be used for. A plain overflow-stress test (no
  // pixel snapshot) catches the layout risk that actually exists today — a
  // `RenderFlex`/text overflow from the two-column Row + IntrinsicHeight
  // under a narrow width and inflated font — for free, and it is written
  // against RatingSummaryCard directly (no HubFlatCard in this pump), so it
  // is unaffected by that pending wrapper removal. See the audit's golden
  // verdict for the full reasoning.
  testWidgets(
    'the two-column distribution table survives 320dp width + 1.3x text '
    'scale without a RenderFlex/text overflow',
    (tester) async {
      await tester.pumpApp(
        _host(
          const RatingSummaryCard(
            avgRating: 4.7,
            reviewCount: 12,
            distribution: <int>[7, 3, 1, 1, 0],
            countLabel: '12 відгуків',
            averageKey: _avgKey,
          ),
        ),
        width: 320,
        textScaleFactor: 1.3,
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'no RenderFlex/text overflow may escape at the narrowest '
            'Android width (320dp) combined with an elevated text scale — '
            'this is the two-column table backlog row 313 named, never '
            'exercised at a stress size before this test',
      );

      // The average and at least one distribution row must still be on
      // screen (not silently clipped to nothing by an overflow guard that
      // only catches RenderFlex, not visual truncation).
      expect(find.byKey(_avgKey), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    },
  );
}
