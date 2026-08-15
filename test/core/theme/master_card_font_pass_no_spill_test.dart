// mobile-qa — 2026-08-15 booking-card font-size pass, THE NO-SPILL GUARANTEE.
//
// The whole pass rests on one claim: `master_booking_card.dart`'s three
// densities shrank ~1sp across the board, and NOTHING outside that card moved
// with them. The mechanism is two frozen/untouched tokens —
// `VelvetText.masterCardTimeShared` (a literal copy of `masterCardTime`'s
// PRE-pass recipe: Nunito 11sp, muted, height 1.2) and `VelvetText.pill()`
// itself, left alone specifically so `core/widgets/price_tag.dart`'s three
// non-booking-card consumers keep rendering it — see `velvet_text.dart`'s
// `masterCardTimeShared` doc and `price_tag.dart`'s `style` field doc.
//
// Before this file, NOTHING proved the wiring actually holds. Every call
// site — `wishlist_row.dart`, `wishlist_compact_card.dart`,
// `passport_derived_block.dart` — points at the frozen tokens *by source*,
// but a future edit ("consolidate `masterCardTimeShared` back into
// `masterCardTime`, they look the same") would compile clean, pass every
// existing test in those three features (none of which assert a painted
// fontSize), and silently shrink every wish-list/passport duration caption
// and price pill along with the booking card's own font-size pass — which
// this pass explicitly did NOT intend (see the doc comments cited above).
//
// Every assertion here reads the FRAMEWORK's resolved `RenderParagraph`
// style off a REAL mounted widget — never the `VelvetText` token compared to
// itself, and never arithmetic. A literal `11` (not `masterCardTime.fontSize`,
// which is now 10) is the independent anchor that makes these regression
// tests, not smoke tests.

import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_derived_block.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_entry_labels.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

WishlistService _masterEntry() => const WishlistService(
  masterServiceId: 'ms-1',
  masterId: 'm-1',
  masterName: 'Марія Іванюк',
  serviceName: 'Манікюр',
  durationMinutes: 45,
  priceDisplay: '800 ₴',
);

/// The style the FRAMEWORK actually paints [finder] with, read off the built
/// [RenderParagraph] — the same technique `declared_time_cards_test.dart`'s
/// `_paintedStyle` uses, and for the identical reason: the raw `Text.style`
/// field is what the call site PASSED, not necessarily what renders.
TextStyle _painted(WidgetTester tester, Finder finder) {
  final RenderParagraph p = tester.renderObject<RenderParagraph>(finder);
  final TextStyle? style = p.text.style;
  expect(style, isNotNull);
  return style!;
}

void main() {
  group('WishlistRow — untouched by the 2026-08-15 booking-card font-size '
      'pass', () {
    testWidgets(
      'the duration caption paints at 11sp (masterCardTimeShared), NOT 10sp '
      '(masterCardTime\'s new, booking-card-only size)',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 320,
              child: WishlistRow(
                item: _masterEntry(),
                onBook: () {},
                onUnfavourite: () {},
              ),
            ),
          ),
        );

        final TextStyle style = _painted(
          tester,
          find.text(_masterEntry().durationLabel()!),
        );
        expect(
          style.fontSize,
          11,
          reason:
              'wishlist_row.dart must render VelvetText.masterCardTimeShared '
              '(frozen 11sp), not VelvetText.masterCardTime (shrunk to 10sp '
              'by the booking-card font-size pass) — this row was explicitly '
              'out of scope for that pass.',
        );
      },
    );

    testWidgets(
      'the price pill measures the pre-pass 21dp box and paints at 11sp '
      '(VelvetText.pill(), unmodified) — no `style` override reaches this '
      'call site',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 320,
              child: WishlistRow(
                item: _masterEntry(),
                onBook: () {},
                onUnfavourite: () {},
              ),
            ),
          ),
        );

        final double pillHeight = tester.getSize(find.byType(PriceTag)).height;
        expect(
          pillHeight,
          21,
          reason:
              'wishlist_row.dart\'s PriceTag(price: …) passes no `style`, so '
              'it must still render pill()\'s 21dp box — a regression here '
              'means PriceTag\'s new `style` default stopped being null-safe.',
        );
        final TextStyle style = _painted(tester, find.text('800 ₴'));
        expect(style.fontSize, 11);
      },
    );
  });

  group('WishlistCompactCard — untouched by the 2026-08-15 booking-card '
      'font-size pass', () {
    testWidgets(
      'the duration caption paints at 11sp (masterCardTimeShared) and the '
      'price pill measures the pre-pass 17dp COMPACT-padding box',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 200,
              child: WishlistCompactCard(
                item: _masterEntry(),
                onBook: () {},
                onUnfavourite: () {},
              ),
            ),
          ),
        );

        final TextStyle durationStyle = _painted(
          tester,
          find.text(_masterEntry().durationLabel()!),
        );
        expect(
          durationStyle.fontSize,
          11,
          reason:
              'wishlist_compact_card.dart must render masterCardTimeShared, '
              'not the booking card\'s shrunk masterCardTime',
        );

        final double pillHeight = tester.getSize(find.byType(PriceTag)).height;
        expect(
          pillHeight,
          17,
          reason:
              'wishlist_compact_card.dart\'s PriceTag passes '
              'verticalPadding: compactVerticalPadding but no `style` — the '
              'box must stay at pill()\'s 17dp, not shrink to '
              'masterCardPricePill\'s 16dp',
        );
      },
    );
  });

  group('PassportDerivedBlock — untouched by the 2026-08-15 booking-card '
      'font-size pass', () {
    testWidgets(
      'the «≈» approximation marker paints at 11sp (masterCardTimeShared) '
      'and the average-spend pill measures the pre-pass 21dp box',
      (WidgetTester tester) async {
        await tester.pumpApp(
          const Center(
            child: SizedBox(
              width: 320,
              child: PassportDerivedBlock(
                districts: <String>['Шевченківський'],
                cities: <String>['Київ'],
                averageSpend: '750 ₴',
              ),
            ),
          ),
        );

        final TextStyle markerStyle = _painted(
          tester,
          find.text(kApproximatelyMarker),
        );
        expect(
          markerStyle.fontSize,
          11,
          reason:
              'passport_derived_block.dart must render masterCardTimeShared '
              'for its «≈» marker, not the booking card\'s shrunk '
              'masterCardTime',
        );

        final double pillHeight = tester.getSize(find.byType(PriceTag)).height;
        expect(
          pillHeight,
          21,
          reason:
              'passport_derived_block.dart\'s PriceTag(price: average) passes '
              'no `style` and no `verticalPadding` — it must render pill()\'s '
              'default 21dp box, unaffected by the booking card\'s own '
              'masterCardPricePill override',
        );
        final TextStyle priceStyle = _painted(tester, find.text('750 ₴'));
        expect(priceStyle.fontSize, 11);
      },
    );
  });
}
