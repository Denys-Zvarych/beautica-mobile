// Phase 4.5 — Widget tests for the shared [ReviewCard] leaf (+ [ReviewStarRow],
// [ReviewAvatar]) in isolation.
//
// The card is feature-neutral by construction (Phase 4.5 extraction): both the
// salon profile and the master "Мої відгуки" screen render every review through
// it. These tests pin its contract independent of either feature:
//   • widget key is `Key('$keyPrefix-${data.id}')` so a list test can target one.
//   • the ★ row fills exactly `rating` stars (accentDeep) of 5.
//   • the masked client name + comment render verbatim.
//   • the service-name sub-line (Icons.spa_outlined) is OMITTED when
//     serviceName is null/empty (the master case) and PRESENT when supplied
//     (the salon case) — rendered as the raw service name with no label.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

ReviewCardData _data({
  String id = 'r-1',
  String clientDisplayName = 'Олена К.',
  int rating = 4,
  String? comment = 'Все чудово, дякую!',
  String? serviceName,
  bool noDate = false,
}) => ReviewCardData(
  id: id,
  clientDisplayName: clientDisplayName,
  rating: rating,
  comment: comment,
  // The two SHIPPED callers (salon + master reviews) always supply a
  // timestamp; `noDate: true` is the phase-334 booking-detail case, whose
  // payload carries none.
  createdAt: noDate ? null : DateTime.utc(2026, 6, 10, 10),
  serviceName: serviceName,
);

/// Every [Text] string currently in the tree, in paint order.
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .toList();

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

  testWidgets('omits the service sub-line when serviceName is null '
      '(the master case)', (tester) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(serviceName: 'Манікюр'),
          keyPrefix: 'master-review',
          // serviceName omitted → null → sub-line hidden even though the
          // data carries a serviceName. This is the master screen's contract.
        ),
      ),
    );

    expect(find.byIcon(Icons.spa_outlined), findsNothing);
  });

  testWidgets('omits the sub-line when serviceName is the empty string', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        ReviewCard(data: _data(), keyPrefix: 'master-review', serviceName: ''),
      ),
    );

    expect(find.byIcon(Icons.spa_outlined), findsNothing);
  });

  testWidgets('renders the service sub-line as the raw service name, with '
      'no «послуга:» label, when serviceName is supplied (the salon case)', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(),
          keyPrefix: 'salon-review',
          serviceName: 'Манікюр',
        ),
      ),
    );

    expect(find.byIcon(Icons.spa_outlined), findsOneWidget);
    // i18n-finder-ok: fixture service-name data, not localised UI copy.
    expect(find.text('Манікюр'), findsOneWidget);
    expect(find.textContaining('послуга'), findsNothing);
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

  // ── Phase 334 — the nullable widening ───────────────────────────────────
  //
  // «Деталі запису»'s provider branch renders the client's review of the
  // master through THIS card (`ClientReviewSection`). Its payload,
  // `ClientAuthoredReviewResponse`, is `{rating, comment?}` and nothing else
  // — no timestamp, and a comment that is genuinely absent when the client
  // rated without writing anything. Both fields were widened to nullable for
  // it.
  //
  // The widening is ADDITIVE, and the two regression tests at the end of this
  // group are the load-bearing half: the salon and master reviews tabs pass
  // non-null values for both, so their cards must render byte-for-byte as
  // before. `null` is the ONLY value that suppresses either line — an EMPTY
  // comment string still renders its (empty) Text and its leading gap, which
  // is what the pre-widening code did unconditionally.

  testWidgets('omits the relative-date line when createdAt is null, keeping '
      'every other line', (tester) async {
    await tester.pumpApp(
      _host(ReviewCard(data: _data(), keyPrefix: 'client-review')),
    );
    final List<String> withDate = _texts(tester);

    await tester.pumpApp(
      _host(ReviewCard(data: _data(noDate: true), keyPrefix: 'client-review')),
    );
    final List<String> withoutDate = _texts(tester);

    // Exactly ONE Text disappears, and it is neither the name nor the
    // comment — i.e. the relative date, without this test having to know what
    // string the formatter produces for a clock it does not control.
    expect(withDate.length, withoutDate.length + 1);
    expect(
      withoutDate,
      containsAll(<String>['Олена К.', 'Все чудово, дякую!']),
    );
    final Set<String> dropped = withDate.toSet().difference(
      withoutDate.toSet(),
    );
    expect(dropped, hasLength(1));
    expect(dropped.single, isNot('Олена К.'));
    expect(dropped.single, isNot('Все чудово, дякую!'));
  });

  testWidgets('omits the comment body when comment is null — the ★ row IS the '
      'review', (tester) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(comment: null, noDate: true),
          keyPrefix: 'client-review',
        ),
      ),
    );

    // The name survives, the body is gone, and the score still renders in
    // full — a stars-only review is a complete review, not an empty state.
    expect(_texts(tester), <String>['Олена К.']);
    // i18n-finder-ok: the fixture review body is backend data, not UI copy.
    expect(find.text('Все чудово, дякую!'), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
    expect(_filledStars(tester), 4);
  });

  testWidgets('REGRESSION — an EMPTY comment still renders its Text, exactly '
      'as before the nullable widening (only null suppresses it)', (
    tester,
  ) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(comment: '', noDate: true),
          keyPrefix: 'salon-review',
        ),
      ),
    );

    // Two Texts: the name and the empty body. Were the guard written
    // `comment != null && comment.isNotEmpty`, this would collapse to one and
    // an existing caller's card would silently lose a row of height.
    expect(_texts(tester), <String>['Олена К.', '']);
  });

  testWidgets('REGRESSION — the shipped callers pass both fields non-null and '
      'get the unchanged three-line card', (tester) async {
    await tester.pumpApp(
      _host(
        ReviewCard(
          data: _data(),
          keyPrefix: 'master-review',
          serviceName: 'Манікюр',
        ),
      ),
    );

    final List<String> texts = _texts(tester);
    // name, relative date, comment, service sub-line — nothing dropped.
    expect(texts, hasLength(4));
    expect(texts.first, 'Олена К.');
    expect(texts, contains('Все чудово, дякую!'));
    expect(texts, contains('Манікюр'));
    expect(find.byIcon(Icons.spa_outlined), findsOneWidget);
  });

  group('onMore (phase 424 D2)', () {
    testWidgets('null (default) → no «⋮» affordance', (tester) async {
      await tester.pumpApp(
        _host(
          ReviewCard(
            data: _data(id: 'a'),
            keyPrefix: 'master-review',
          ),
        ),
      );
      expect(find.byType(ReviewMoreButton), findsNothing);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(
        find.byKey(ReviewCard.moreKey('master-review', 'a')),
        findsNothing,
      );
    });

    testWidgets('non-null → «⋮» under its key; a tap calls onMore once', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpApp(
        _host(
          ReviewCard(
            data: _data(id: 'a'),
            keyPrefix: 'salon-review',
            onMore: () => taps++,
          ),
        ),
      );
      final Finder more = find.byKey(ReviewCard.moreKey('salon-review', 'a'));
      expect(more, findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

      // Tap BY KEY with the hit-test warning fatal: the key must sit on the
      // hit target (the GestureDetector), not on the Transform root, whose
      // `RenderTransform` never joins the hit path.
      final bool savedFatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal = savedFatal,
      );
      await tester.tap(more);
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('«⋮» does not grow the card (header stays 40 dp tall)', (
      tester,
    ) async {
      await tester.pumpApp(
        _host(
          ReviewCard(
            data: _data(id: 'a'),
            keyPrefix: 'k',
          ),
        ),
      );
      final double plain = tester.getSize(find.byKey(const Key('k-a'))).height;
      await tester.pumpApp(
        _host(
          ReviewCard(
            data: _data(id: 'a'),
            keyPrefix: 'k',
            onMore: () {},
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('k-a'))).height, plain);
    });
  });
}
