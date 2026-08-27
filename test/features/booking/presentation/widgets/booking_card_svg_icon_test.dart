// Phase — category icons on the «МОЇ ЗАПИСИ» booking card.
//
// `BookingCard`'s `_categoryIconFor` was a private card-local `switch` over
// Ukrainian display-name literals ('Манікюр', 'Волосся', …). The wire never
// sends those — `categoryName` carries the raw UPPER_SNAKE slug
// (`service_definitions.category`) — so every card silently fell through to
// the single default `Icons.auto_awesome_rounded`. This file pins the fix:
// the card now resolves through the shared `categoryIconOrNullFor` (see
// `core/icons/category_icons.dart`), preferring `Booking.categoryKey` (the
// new nullable slug field, threaded from `BookingDetailResponse.categoryKey`)
// with `categoryName` as the documented fallback.
//
// ── Height contract ─────────────────────────────────────────────────────
//
// `_ServiceLine._iconSize` stays at 14dp — NOT the 20dp seven other list-row
// surfaces settled on (`service_category_cards.dart`,
// `service_category_list.dart`, `salon_services_accordion.dart`, …).
// Measured directly (`tester.getSize`) before this file existed: bumping to
// 20dp grows a ONE-LINE-service-name card from 115.0dp to 121.0dp (+6dp) —
// the icon column (20+1dp top padding = 21dp) then exceeds the one-line
// service text's own height (13.75dp) and becomes the row's tallest child.
// A two-line service name is unaffected either way (128.0dp both), because
// the text (27.5dp) already dominates. At 14dp the icon column (15dp) was
// ALREADY the taller child in the one-line case even under the old Material
// glyph, so keeping 14dp is a pure glyph-source swap with NO height change.
// The first group below pins that invariant directly, so a future bump to
// 20 "to match the other surfaces" fails loudly here first.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/booking_fixture_dates.dart';
import '../../../../helpers/pump_app.dart';

Booking _booking({
  required String id,
  required String serviceName,
  String? categoryKey,
  String? categoryName,
}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: 'SALON_MASTER',
    salonName: 'Lviv Nails Studio',
    serviceId: 'service-$id',
    serviceName: serviceName,
    categoryKey: categoryKey,
    categoryName: categoryName,
    cityLabel: 'Львів',
    districtLabel: 'Залізничний район',
    street: 'вулиця Тестова',
    buildingNo: '15А',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
    masterProfessionalTitle: 'Майстриня манікюру',
  );
}

void main() {
  group('BookingCard — category icon height contract', () {
    testWidgets('a categorised one-line-service card is the SAME height as an '
        'uncategorised one (icon slot never reflows the row)', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: <Widget>[
              BookingCard(
                booking: _booking(
                  id: 'cat',
                  serviceName: 'Манікюр',
                  categoryKey: 'NAIL_SERVICE',
                ),
                onOpenDetails: () {},
              ),
              BookingCard(
                booking: _booking(id: 'nocat', serviceName: 'Манікюр'),
                onOpenDetails: () {},
              ),
            ],
          ),
        ),
        width: 360,
      );
      await tester.pump();

      final double categorised = tester
          .getSize(find.byKey(const ValueKey<String>('stub-cat')))
          .height;
      // The stub key is per-card but the CARD height is what matters —
      // measure the BookingCard ancestor of each service Text instead.
      final double catCardHeight = tester
          .getSize(
            find.ancestor(
              of: find.byKey(const ValueKey<String>('service-cat')),
              matching: find.byType(BookingCard),
            ),
          )
          .height;
      final double noCatCardHeight = tester
          .getSize(
            find.ancestor(
              of: find.byKey(const ValueKey<String>('service-nocat')),
              matching: find.byType(BookingCard),
            ),
          )
          .height;

      expect(
        catCardHeight,
        noCatCardHeight,
        reason:
            'the 14dp icon slot must not change the card height whether '
            'an icon renders or not',
      );
      // Sanity: the stub measurement above is reachable (guards a dead
      // finder from silently vacuous-passing the test).
      expect(categorised, greaterThan(0));

      // ── The parity check above (cat == nocat) holds at ANY _iconSize
      //    value, since both cards always reserve the same slot width —
      //    it is INVARIANT to a regression that bumps _iconSize for every
      //    card equally, which is exactly the mutation this group's doc
      //    comment claims to catch ("a future bump to 20 ... fails loudly
      //    here first"). It does not, on its own. Pin the ABSOLUTE
      //    measured height too, so a size bump that grows every one-line
      //    card in lockstep is caught directly instead of only by the
      //    unrelated `icon.size` constructor-field read in the next group
      //    (mobile-qa mutation-test gap closure, 2026-08-27 — verified via
      //    `tester.getSize`, not a field read; see `project_widget_field_
      //    assertion_is_vacuous` for why the field read alone would not
      //    suffice).
      expect(
        catCardHeight,
        closeTo(115.0, 0.5),
        reason:
            'the one-line-service card must stay at 115dp; a bump to 20dp '
            'grows it to 121dp per this file\'s header measurement — this '
            'assertion is what actually pins that, not the cat==nocat '
            'parity check above',
      );
    });
  });

  group('BookingCard — categoryKey preferred, categoryName fallback', () {
    testWidgets('resolves the SVG icon from categoryKey (slug)', (
      tester,
    ) async {
      await tester.pumpApp(
        Scaffold(
          body: BookingCard(
            booking: _booking(
              id: 'k',
              serviceName: 'Манікюр з покриттям',
              categoryKey: 'NAIL_SERVICE',
              categoryName: null,
            ),
            onOpenDetails: () {},
          ),
        ),
        width: 360,
      );
      await tester.pump();

      final AppIcon icon = tester.widget<AppIcon>(find.byType(AppIcon));
      expect(icon.asset, BeauticaAssetIcons.categoryNailService);
      expect(icon.size, 14);
    });

    testWidgets('BROWS and LASH_EXTENSIONS resolve to DIFFERENT icons '
        '(the old switch collapsed both onto one eye glyph)', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: <Widget>[
              BookingCard(
                booking: _booking(
                  id: 'brows',
                  serviceName: 'Корекція брів',
                  categoryKey: 'BROWS',
                ),
                onOpenDetails: () {},
              ),
              BookingCard(
                booking: _booking(
                  id: 'lash',
                  serviceName: 'Нарощування вій',
                  categoryKey: 'LASH_EXTENSIONS',
                ),
                onOpenDetails: () {},
              ),
            ],
          ),
        ),
        width: 360,
      );
      await tester.pump();

      final List<AppIcon> icons = tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .toList();
      expect(icons, hasLength(2));
      expect(icons[0].asset, isNot(icons[1].asset));
      expect(icons[0].asset, BeauticaAssetIcons.categoryBrows);
      expect(icons[1].asset, BeauticaAssetIcons.categoryLashExtensions);
    });

    testWidgets('no categoryKey falls back to categoryName keyword match '
        '(exercises the shared two-stage contract; on the REAL booking wire '
        'categoryName is itself the raw slug, not Ukrainian text, so this '
        'fallback stage is realistically dead for this call site — it is '
        'still passed, per the ticket, as the documented fallback)', (
      tester,
    ) async {
      await tester.pumpApp(
        Scaffold(
          body: BookingCard(
            booking: _booking(
              id: 'name-fallback',
              serviceName: 'Стрижка',
              categoryKey: null,
              categoryName: 'Стрижка та укладання волосся',
            ),
            onOpenDetails: () {},
          ),
        ),
        width: 360,
      );
      await tester.pump();

      final AppIcon icon = tester.widget<AppIcon>(find.byType(AppIcon));
      expect(icon.asset, BeauticaAssetIcons.categoryHairdressing);
    });

    testWidgets('both categoryKey and categoryName absent renders NO icon '
        '(SizedBox placeholder only — never the cosmetology fallback)', (
      tester,
    ) async {
      await tester.pumpApp(
        Scaffold(
          body: BookingCard(
            booking: _booking(
              id: 'blank',
              serviceName: 'Невідома послуга',
              categoryKey: null,
              categoryName: null,
            ),
            onOpenDetails: () {},
          ),
        ),
        width: 360,
      );
      await tester.pump();

      expect(find.byType(AppIcon), findsNothing);
    });
  });
}
