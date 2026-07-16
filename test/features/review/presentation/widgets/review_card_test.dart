// Phase 4.5 — Widget tests for the shared [ReviewCard] leaf (+ [ReviewStarRow],
// [ReviewAvatar]) in isolation.
//
// The card is feature-neutral by construction (Phase 4.5 extraction): both the
// salon profile and the master "Мої відгуки" screen render every review through
// it. These tests pin its contract independent of either feature:
//   • widget key is `Key('$keyPrefix-${data.id}')` so a list test can target one.
//   • the ★ row fills exactly `rating` stars (accentDeep) of 5.
//   • the masked client name + comment render verbatim.
//   • the «послуга:» sub-line (Icons.spa_outlined) is OMITTED when servicePrefix
//     is null/empty (the master case) and PRESENT when supplied (the salon case).

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

ReviewCardData _data({
  String id = 'r-1',
  String clientDisplayName = 'Олена К.',
  int rating = 4,
  String comment = 'Все чудово, дякую!',
  String? serviceName,
}) => ReviewCardData(
  id: id,
  clientDisplayName: clientDisplayName,
  rating: rating,
  comment: comment,
  createdAt: DateTime.utc(2026, 6, 10, 10),
  serviceName: serviceName,
);

Widget _host(ReviewCard card) => Scaffold(body: Center(child: card));

/// Counts the star icons rendered with the "filled" colour ([accentDeep]).
int _filledStars(WidgetTester tester) {
  return tester
      .widgetList<Icon>(find.byIcon(Icons.star_rounded))
      .where((Icon i) => i.color == BrandColors.accentDeep)
      .length;
}

void main() {
  testWidgets('renders under the composed keyPrefix-id key', (tester) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(id: 'abc'),
          keyPrefix: 'master-review',
        ),
      ),
    );

    expect(find.byKey(const Key('master-review-abc')), findsOneWidget);
  });

  testWidgets('★ row fills exactly `rating` of 5 stars', (tester) async {
    await tester.pumpApp(
      _host(ReviewCard(data: _data(rating: 3), keyPrefix: 'master-review')),
    );

    // 5 stars total; exactly 3 are the filled accentDeep colour.
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
    expect(_filledStars(tester), 3);
  });

  testWidgets('renders the masked client name and comment verbatim', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(
            clientDisplayName: 'Ірина П.',
            comment: 'Майстер золоті руки!',
          ),
          keyPrefix: 'master-review',
        ),
      ),
    );

    // i18n-finder-ok: masked name is backend data, not UI copy.
    expect(find.text('Ірина П.'), findsOneWidget);
    // i18n-finder-ok: review comment is backend data, not UI copy.
    expect(find.text('Майстер золоті руки!'), findsOneWidget);
  });

  testWidgets('omits the «послуга» sub-line when servicePrefix is null '
      '(the master case)', (tester) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(serviceName: 'Манікюр'),
          keyPrefix: 'master-review',
          // servicePrefix omitted → null → sub-line hidden even though the
          // data carries a serviceName. This is the master screen's contract.
        ),
      ),
    );

    expect(find.byIcon(Icons.spa_outlined), findsNothing);
  });

  testWidgets('omits the sub-line when servicePrefix is the empty string', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(),
          keyPrefix: 'master-review',
          servicePrefix: '',
        ),
      ),
    );

    expect(find.byIcon(Icons.spa_outlined), findsNothing);
  });

  testWidgets('renders the «послуга» sub-line when servicePrefix is supplied '
      '(the salon case)', (tester) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(),
          keyPrefix: 'salon-review',
          servicePrefix: 'послуга: Манікюр',
        ),
      ),
    );

    expect(find.byIcon(Icons.spa_outlined), findsOneWidget);
    // i18n-finder-ok: caller passes an already-formatted string; asserting the exact text the widget was handed, not a localised key resolved internally.
    expect(find.text('послуга: Манікюр'), findsOneWidget);
  });

  testWidgets('a rating of 0 fills no stars (still renders 5 outlines)', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(ReviewCard(data: _data(rating: 0), keyPrefix: 'master-review')),
    );

    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
    expect(_filledStars(tester), 0);
  });
}
