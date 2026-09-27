// Widget tests for `RatingSummaryLine` (lib/shared/widgets/rating_summary_line.dart).
//
// Phase 351 (mobile-qa gap-fix, 2026-09-25) — `RatingSummaryLine` was
// PROMOTED from the private rating row inside `_SalonHeroCard`
// (`public_salon_profile_screen.dart`) with ZERO direct widget tests. The
// salon hero card's own screen test proves it renders in context; this file
// proves the widget's own branch logic in isolation:
//   1. `rating == null` renders the em-dash placeholder «—», never "null" or
//      an empty string.
//   2. `reviewCount == 0` renders the count label for zero (a real,
//      renderable fact, distinct from "no rating").
//   3. A real rating formats to exactly 1 decimal place (`4.8`, not `4.80` or
//      `4.8000000001`).
//   4. `ratingKey` / `countKey` land on the correct `Text` widgets — the
//      contract every caller's finder depends on.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/rating_summary_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('uk'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('RatingSummaryLine — rating branch', () {
    testWidgets('rating == null renders the em-dash placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RatingSummaryLine(
            rating: null,
            reviewCount: 0,
            ratingKey: Key('rating-value'),
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('rating-value'))).data,
        '—',
      );
    });

    testWidgets('a real rating formats to exactly 1 decimal place', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RatingSummaryLine(
            rating: 4.8,
            reviewCount: 12,
            ratingKey: Key('rating-value'),
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('rating-value'))).data,
        '4.8',
      );
    });

    testWidgets('a rating with more precision still renders 1 decimal '
        'place (4.75 -> 4.8, half-up)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RatingSummaryLine(
            rating: 4.75,
            reviewCount: 3,
            ratingKey: Key('rating-value'),
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('rating-value'))).data,
        '4.8',
      );
    });

    testWidgets('star icon always renders regardless of rating value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const RatingSummaryLine(rating: null, reviewCount: 0)),
      );

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });
  });

  group('RatingSummaryLine — reviewCount branch', () {
    testWidgets('reviewCount == 0 renders the zero-count label, not blank', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RatingSummaryLine(
            rating: 4.5,
            reviewCount: 0,
            countKey: Key('count-value'),
          ),
        ),
      );

      final Text countText = tester.widget<Text>(
        find.byKey(const Key('count-value')),
      );
      expect(countText.data, isNotNull);
      expect(countText.data, isNotEmpty);
      // i18n-finder-ok: asserting the generated plural-zero wording renders,
      // not translating UI copy ourselves — mirrors the ARB "=0" branch.
      expect(countText.data, contains('0'));
    });

    testWidgets('a non-zero count renders that number in the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RatingSummaryLine(
            rating: 4.5,
            reviewCount: 12,
            countKey: Key('count-value'),
          ),
        ),
      );

      final Text countText = tester.widget<Text>(
        find.byKey(const Key('count-value')),
      );
      expect(countText.data, contains('12'));
    });
  });

  group('RatingSummaryLine — key wiring', () {
    testWidgets('ratingKey and countKey are independent — each lands on its '
        'own Text, not swapped', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RatingSummaryLine(
            rating: 4.8,
            reviewCount: 12,
            ratingKey: Key('r'),
            countKey: Key('c'),
          ),
        ),
      );

      expect(tester.widget<Text>(find.byKey(const Key('r'))).data, '4.8');
      expect(
        tester.widget<Text>(find.byKey(const Key('c'))).data,
        contains('12'),
      );
    });

    testWidgets('omitting both keys renders without throwing (keys are '
        'optional)', (tester) async {
      await tester.pumpWidget(
        _wrap(const RatingSummaryLine(rating: 4.8, reviewCount: 12)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('4.8'), findsOneWidget);
    });
  });
}
