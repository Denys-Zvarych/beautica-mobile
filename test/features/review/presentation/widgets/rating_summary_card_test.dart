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
}
