// mobile-qa Part 3 — regression test for `BookingSummaryCards`' `dense`
// flag (`booking_summary_cards.dart`). `BookingConfirmScreen` now passes
// `dense: true` to tighten the address/date/time details card's internal
// spacing (was left at the roomy default). This pins that `dense: true`
// actually measurably shrinks the rendered card — i.e. the flag is really
// wired into the padding/section-rule/`BookingRecap` spacing, not merely
// threaded through as an inert constructor argument that never reaches any
// layout.
//
// Isolated via `showMasterCard: false` so `find.byType(NeumorphicCard)`
// matches exactly the ONE details card under test — `MasterStrip` (rendered
// when `showMasterCard: true`) is itself built on a `NeumorphicCard`, but it
// does not receive `dense` at all, so including it would both make the
// finder ambiguous (two cards) and dilute the height comparison with a card
// whose size is unrelated to this flag.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_cards.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
);

const _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'NAILS',
);

void main() {
  group('BookingSummaryCards dense mode', () {
    Future<double> pumpDetailsCardHeight(
      WidgetTester tester, {
      required bool dense,
    }) async {
      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: BookingSummaryCards(
              master: _kMaster,
              service: _kService,
              start: DateTime(2026, 7, 20, 14),
              showMasterCard: false,
              dense: dense,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder card = find.byType(NeumorphicCard);
      expect(card, findsOneWidget);
      return tester.getSize(card).height;
    }

    testWidgets('dense: true renders a measurably shorter details card than '
        'dense: false, for the identical booking data', (tester) async {
      final double denseHeight = await pumpDetailsCardHeight(
        tester,
        dense: true,
      );
      final double roomyHeight = await pumpDetailsCardHeight(
        tester,
        dense: false,
      );

      expect(
        denseHeight,
        lessThan(roomyHeight),
        reason:
            'dense:true tightens the card padding (VelvetSpacing.sm+4 vs '
            '.md), the two _SectionRule gaps, and the inter-row spacing '
            'before the "Час" row — if `dense` were only threaded through '
            'as an inert flag (e.g. forwarded to BookingRecap but never '
            'read by the card\'s own Padding/_SectionRule), both renders '
            'would come out the SAME height and this assertion would '
            'catch it.',
      );

      // Sanity bound: the compact-mode saving from `booking_summary_cards
      // .dart`'s own spacing constants is at least ~24dp (2 tightened
      // section rules alone save `2 * (VelvetSpacing.md -
      // (VelvetSpacing.sm + 2))` = `2 * (16 - 10)` = 12dp, plus the card's
      // own outer padding shrinks by `2 * (VelvetSpacing.md -
      // (VelvetSpacing.sm + 4))` = `2 * (16 - 12)` = 8dp, plus a further
      // 4dp from the pre-"Час" row gap — comfortably over 20dp total).
      // A trivial 1px difference (e.g. from float rounding rather than a
      // real spacing change) would fail this stricter bound while still
      // passing the plain `lessThan` above.
      expect(roomyHeight - denseHeight, greaterThan(20));
    });
  });

  // mobile-qa regression — `showBorder` pass-through. `BookingSummaryCards`
  // forwards its own `showBorder` param straight to the details
  // `NeumorphicCard`'s `showBorder`; this was wired but never exercised by
  // any test. Isolated via `showMasterCard: false` for the same reason as
  // the `dense` group above — the master card is itself built on a
  // `NeumorphicCard` that never receives `showBorder`, so including it would
  // make `find.byType(NeumorphicCard)` ambiguous.
  group('BookingSummaryCards showBorder pass-through', () {
    Future<void> pumpCard(WidgetTester tester, {required bool showBorder}) =>
        tester.pumpApp(
          Scaffold(
            body: BookingSummaryCards(
              master: _kMaster,
              service: _kService,
              start: DateTime(2026, 7, 20, 14),
              showMasterCard: false,
              showBorder: showBorder,
            ),
          ),
        );

    testWidgets(
      'showBorder: false (default, unset) does not reach the details '
      'NeumorphicCard',
      (tester) async {
        await pumpCard(tester, showBorder: false);
        await tester.pumpAndSettle();

        final Finder cardFinder = find.byType(NeumorphicCard);
        expect(cardFinder, findsOneWidget);
        final NeumorphicCard card = tester.widget<NeumorphicCard>(cardFinder);
        expect(
          card.showBorder,
          isFalse,
          reason:
              'BookingSummaryCards(showBorder: false) must not opt the '
              'details NeumorphicCard into the border.',
        );
      },
    );

    testWidgets(
      'showBorder: true reaches the details NeumorphicCard and renders the '
      'hairline stroke',
      (tester) async {
        await pumpCard(tester, showBorder: true);
        await tester.pumpAndSettle();

        final Finder cardFinder = find.byType(NeumorphicCard);
        expect(cardFinder, findsOneWidget);
        final NeumorphicCard card = tester.widget<NeumorphicCard>(cardFinder);
        expect(
          card.showBorder,
          isTrue,
          reason:
              'BookingSummaryCards(showBorder: true) must forward showBorder '
              'straight through to the details NeumorphicCard.',
        );

        // Also confirm the border actually renders — not merely that the
        // flag reached the constructor argument.
        final DecoratedBox decoratedBox = tester.widget<DecoratedBox>(
          find
              .descendant(of: cardFinder, matching: find.byType(DecoratedBox))
              .first,
        );
        final BoxDecoration decoration =
            decoratedBox.decoration as BoxDecoration;
        expect(
          decoration.border,
          equals(Border.all(color: BrandColors.faint, width: 1)),
        );
      },
    );
  });
}
