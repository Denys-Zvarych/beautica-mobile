// Phase 7.10 timeline audit (R2 regression) — direct CARD-level pin.
//
// `bookings_timeline_grid_test.dart`'s "short bookings render their full
// card, not a clipped sliver" group already proves the fix in the TIMELINE's
// context: nothing upstream of `MasterBookingCard` computes or passes a
// forced height any more. This file proves the OTHER half — that
// `MasterBookingCard` itself has no internal mechanism left that COULD clip
// its own content, regardless of what a duration-derived box used to do to
// it. See `master_booking_card.dart`'s class doc for the retired
// `OverflowBox` + `ClipRect` pair this pins against reintroducing: an earlier
// version wrapped the card in that pair whenever an externally-forced
// `height:` came in smaller than the card's natural size (as it always did
// for anything shorter than ~50 minutes) — laying the card out at its full
// natural height and then visually CROPPING the paint (and the hit-test
// region) down to the forced box. That was the exact mechanism behind the
// real-device report: "I can see only half of the card, and another card is
// cut off".
//
// `MasterBookingCard` no longer accepts a `width`/`height` constructor param
// at all (only `booking` + `onTap` + a `minHeight` FLOOR), so there is no
// longer any external knob that could reintroduce the old clip.
//
// THE COMPACT LAYOUT IS NOW A MINIATURE OF THE FULL ONE (2026-07-21)
// -------------------------------------------------------------------
// The compact body was re-composed from a divider-less two-row grid
// (time/service/price, then client/status) into a scaled-down copy of the
// >=1h card's own shape:
//
//   row 1  client name (flexes) · start–end range · status DOT
//   ─────  hairline
//   row 2  service name (flexes) · price
//
// Three structural consequences this file now pins, none of which the old
// suite could express:
//
//   * BOTH layouts carry a hairline, so "is there a divider" no longer tells
//     them apart. Each has its OWN key — `master-booking-card-compact-
//     divider-<id>` vs `master-booking-card-divider-<id>` — and every
//     layout-selection assertion keys off which one rendered AND that the
//     other did not.
//   * The compact layout renders `TimelineStatusDot` (8dp circle, label in
//     `Semantics`/`Tooltip`); the FULL layout keeps the labelled
//     `TimelineStatusBadge`. Presence of one and absence of the other is the
//     second, independent layout probe.
//   * The vertical budget is now EXACT — 39dp of content in a 54dp box at
//     textScaler 1.0 (41dp/56dp before the 2026-08-15 font-size pass — see
//     `velvet_text.dart`'s `masterCardClientName` doc), zero slack — where
//     the outgoing layout measured 55dp against a 56dp box and carried ~1dp
//     of slop. The "39dp vertical budget" group below is new: the previous
//     suite only ever guarded
//     WIDTH, so a regression that ate a gap or re-inflated the price pill
//     had nothing to fail against.
//
// TIME IS A RANGE, AND CARRIES NO DATE (2026-07-21)
// -------------------------------------------------
// BOTH layouts print `start–end` via `formatSlotTimeRange(startAt, endAt)`,
// and NEITHER prints a date («Мої записи» is day-scoped and the day rail
// already names the day). Two things are asserted throughout, both of which a
// naive "the range renders" check would miss:
//
//   * NO DATE anywhere on the card — checked against the fixture's own
//     `monthAbbrev` token rather than a Cyrillic literal, so it survives
//     both the i18n-finder gate and a change of fixture date.
//   * The range comes from `endAt`, NOT from `startAt + durationMinutes`. The
//     "endAt is the source of truth" case below deliberately hands the
//     fixture an `endAt` that disagrees with its `durationMinutes`, which is
//     the only shape that can tell the two derivations apart.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
// `rendering.dart` (for RenderParagraph) re-exports `semantics.dart`, which
// this file also uses — importing both trips `unnecessary_import`.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

Booking _shortBooking({
  String id = 'short-card',
  int durationMinutes = 20,
  BookingStatus status = BookingStatus.confirmed,
}) {
  // WHY A PINNED INSTANT AND NOT `futureBookingStart()` (stale-future-date
  // gate, 2026-07-21)
  // -----------------------------------------------------------------------
  // Every assertion in this file that touches time is a WALL-CLOCK STRING
  // assertion derived from this instant: the «09:00–09:20» range the card
  // prints, its measured dp width in the narrow-lane sweeps below (a
  // now-relative anchor makes the label 1-2 glyphs wider or narrower
  // depending on the hour it lands on, which silently moves every measured
  // overflow floor), and the `monthAbbrev` no-date probe in
  // `_expectNoDateOnCard`. Expiry cannot change any outcome either:
  // `MasterBookingCard` renders nothing off `BookingDisplayX.isPast` — the
  // status indicator maps from `booking.status` alone and `showsPrice` is a
  // pure status predicate — so this fixture is inert with respect to "now" by
  // construction, not by luck.
  // future-date-ok: pinned Kyiv wall-clock fixture — see the block above.
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6); // 09:00 Kyiv
  return Booking(
    id: id,
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    serviceName: 'Стрижка жіноча',
    durationMinutes: durationMinutes,
    price: 450,
    startAt: startAt,
    endAt: startAt.add(Duration(minutes: durationMinutes)),
    status: status,
    canReview: false,
  );
}

void main() {
  // ONE TIME STYLE ACROSS ALL THREE DENSITIES (2026-07-24)
  // ---------------------------------------------------------------------
  // The reported bug: a lane mixes densities freely (a 30-minute booking
  // sits directly under a 90-minute one), and the range was typeset in two
  // unrelated recipes — `masterCardDateFull` (Nunito 11, muted) on the FULL
  // body against a `bodyStrong` 11.5 sp in `BrandColors.text` on COMPACT and
  // MICRO. Different base style, different size AND different colour, all
  // visible side by side on one timeline.
  //
  // This group asserts the property directly off the RENDERED paragraphs
  // rather than off the token identity, so it survives a future refactor
  // that renames or re-homes either token, and it cannot be satisfied by a
  // regenerated golden. `masterCardTime` is now literally
  // `masterCardDateFull.copyWith(height: 1.2)`; `height` is EXCLUDED from
  // the comparison on purpose and is the one axis allowed to differ — it is
  // a layout knob (the micro body is a single text row, so the tallest
  // child's line box IS the card's height, and `_feedbackBase`'s 1.4 leading
  // would push `microLayoutNaturalHeight` to 30dp and leave a 15-minute
  // booking zero clearance over its own gridline). Every axis a reader can
  // actually SEE — family, size, weight, colour, letter spacing — must match.
  group('the start–end range is typeset identically on all three bodies', () {
    // (floor, layout name) — one per density, read through the card's own
    // published thresholds rather than by quoting duration numbers.
    final List<(double, String)> densities = <(double, String)>[
      (1, 'micro'),
      (MasterBookingCard.microLayoutMaxHeight, 'compact'),
      (MasterBookingCard.fullLayoutMinHeight, 'full'),
    ];

    testWidgets('same family, size, weight, colour and letter spacing — only '
        'the line-box `height` may differ', (WidgetTester tester) async {
      final Booking booking = _shortBooking(id: 'one-time-style');
      final String range = formatSlotTimeRange(booking.startAt, booking.endAt);

      final Map<String, TextStyle> resolved = <String, TextStyle>{};
      for (final (double floor, String name) in densities) {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 272,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: floor,
              ),
            ),
          ),
        );
        await tester.pump();

        final RenderParagraph p = tester.renderObject<RenderParagraph>(
          find.text(range),
        );
        final TextStyle? style = p.text.style;
        expect(
          style,
          isNotNull,
          reason:
              'the $name body\'s range lost its explicit style and is now '
              'inheriting DefaultTextStyle — that is a silent divergence '
              'from the other two densities',
        );
        resolved[name] = style!;
      }

      final TextStyle reference = resolved['full']!;
      for (final MapEntry<String, TextStyle> e in resolved.entries) {
        if (e.key == 'full') continue;
        final TextStyle actual = e.value;
        expect(
          <Object?>[
            actual.fontFamily,
            actual.fontSize,
            actual.fontWeight,
            actual.color,
            actual.letterSpacing,
          ],
          <Object?>[
            reference.fontFamily,
            reference.fontSize,
            reference.fontWeight,
            reference.color,
            reference.letterSpacing,
          ],
          reason:
              'the ${e.key} body\'s time range no longer matches the FULL '
              'card\'s. A master scrolling one lane sees both at once, so '
              'they must read as ONE time style — fix the token '
              '(VelvetText.masterCardTime derives from masterCardDateFull), '
              'never by inlining a style at the call site.',
        );
      }
    });

    testWidgets(
      'the FULL card is still the reference: its range keeps the muted '
      'colour and the schedule_outlined glyph beside it',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(
          id: 'one-time-style-full',
          durationMinutes: 60,
        );
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 272,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: MasterBookingCard.fullLayoutMinHeight,
              ),
            ),
          ),
        );
        await tester.pump();

        final RenderParagraph p = tester.renderObject<RenderParagraph>(
          find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
        );
        expect(
          p.text.style?.color,
          BrandColors.muted,
          reason:
              'the FULL body is the reference recipe the other two were '
              'brought onto — if IT drifts, the comparison above passes '
              'while every density drifts together',
        );
        expect(
          find.byIcon(Icons.schedule_outlined),
          findsOneWidget,
          reason:
              'the glyph is FULL-only (compact/micro have no room for a '
              'second metadata slot) and was explicitly out of scope for '
              'the one-time-style pass',
        );
      },
    );
  });

  group(
    'R2 regression — a short booking renders every row, none truncated',
    () {
      testWidgets(
        'a 20-minute CONFIRMED booking shows the time range, client name, a '
        'hairline, the service name, the price and a status dot all at once',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking();

          // `Center` matters here, not just cosmetics: `pumpApp` places the
          // card directly as `MaterialApp.home`, which receives TIGHT
          // constraints equal to the full test surface (800×600) — without a
          // loosening ancestor, `tester.getSize` would report 600 (the
          // screen height the Column is forced to fill), not the card's real
          // content-driven height. `Center` passes LOOSE constraints to its
          // child, so the card sizes to its own content as it does inside
          // `BookingsTimelineGrid`'s `SingleChildScrollView` in production.
          await tester.pumpApp(
            Center(
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          );
          await tester.pump();

          // No leftover mechanism that could crop the card's paint/hit-test to
          // a smaller box — the exact shape of the retired bug.
          expect(
            find.ancestor(
              of: find.byKey(const Key('master-booking-card-short-card')),
              matching: find.byType(OverflowBox),
            ),
            findsNothing,
          );
          expect(
            find.ancestor(
              of: find.byKey(const Key('master-booking-card-short-card')),
              matching: find.byType(ClipRect),
            ),
            findsNothing,
          );

          // Row 1 — start–end range + client name + the status dot.
          // `formatSlotTimeRange` is the same shared formatter the card uses
          // internally. The client name is asserted against
          // `booking.clientName` (the same `BookingDisplayX` getter the widget
          // renders) rather than a re-typed literal, so the fixture's Cyrillic
          // name isn't duplicated as a second, driftable source of truth.
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          expect(find.text(booking.clientName!), findsOneWidget);
          expect(find.byType(TimelineStatusDot), findsOneWidget);

          // The bare start time alone must NOT be what renders — that is
          // exactly the pre-range behaviour this replaced.
          expect(find.text(formatSlotTime(booking.startAt)), findsNothing);
          _expectNoDateOnCard(booking);

          // The hairline, and row 2 — service name + price.
          expect(
            find.byKey(
              const Key('master-booking-card-compact-divider-short-card'),
            ),
            findsOneWidget,
          );
          expect(find.text(booking.serviceName), findsOneWidget);
          expect(find.text('450 ₴'), findsOneWidget);

          // The compact layout compresses the badge to a dot — the labelled
          // pill belongs to the >=1h card only.
          expect(find.byType(TimelineStatusBadge), findsNothing);

          // Belt-and-braces: the card's real rendered height is exactly the
          // compact body's natural (54dp —
          // `MasterBookingCard.estimatedNaturalHeight`, was 56dp before the
          // 2026-08-15 font-size pass), i.e. every row above genuinely
          // contributed to layout rather than being painted then cropped
          // away. No `minHeight` is passed here —
          // this pumps the card's own NATURAL size, unaffected by the
          // timeline's duration-floor mechanism.
          final double height = tester
              .getSize(find.byKey(const Key('master-booking-card-short-card')))
              .height;
          expect(height, greaterThan(48));
          expect(height, lessThanOrEqualTo(56));
        },
      );

      testWidgets('an even shorter 15-minute booking still shows every row', (
        WidgetTester tester,
      ) async {
        final Booking booking = _shortBooking(
          id: 'short-15',
          durationMinutes: 15,
        );

        // `Center` matters here for the same reason as the sibling test
        // above (see its comment): without it, `pumpApp`'s
        // `MaterialApp.home` hands the card TIGHT constraints equal to the
        // full test surface, and — since the adaptive-layout pass — a
        // `minHeight` that large would trip the >=115dp full-layout switch
        // and render the full body instead of the compact grid this test is
        // about. (Both bodies now print the SAME range string AND carry a
        // hairline, so the switch is only observable through WHICH divider
        // key rendered and whether the status indicator is a dot or a pill.)
        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(
          find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
          findsOneWidget,
        );
        expect(find.text(booking.serviceName), findsOneWidget);
        expect(find.text(booking.clientName!), findsOneWidget);
        expect(find.text('450 ₴'), findsOneWidget);
        expect(find.byType(TimelineStatusDot), findsOneWidget);
        expect(
          find.byKey(const Key('master-booking-card-compact-divider-short-15')),
          findsOneWidget,
        );
      });

      // The miniature layout's reading order, asserted structurally rather
      // than by presence: row 1 (identity) above the hairline, row 2
      // (transaction) below it. This is the property that makes the compact
      // card a MINIATURE of `_buildFullBody` rather than a differently-shaped
      // card that happens to show the same fields — and a "tidy-up" that
      // reordered the Column would keep every presence assertion above green.
      testWidgets(
        'the hairline sits between the identity row and the transaction row',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking(id: 'order-card');

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          );
          await tester.pump();

          final Finder timeFinder = find.text(
            formatSlotTimeRange(booking.startAt, booking.endAt),
          );
          final double timeY = tester.getTopLeft(timeFinder).dy;
          final double nameY = tester
              .getTopLeft(find.text(booking.clientName!))
              .dy;
          final double dividerY = tester
              .getTopLeft(
                find.byKey(
                  const Key('master-booking-card-compact-divider-order-card'),
                ),
              )
              .dy;
          final double serviceY = tester
              .getTopLeft(find.text(booking.serviceName))
              .dy;
          final double priceY = tester.getTopLeft(find.text('450 ₴')).dy;

          expect(
            timeY,
            lessThan(dividerY),
            reason: 'the time range must render above the hairline',
          );
          expect(
            nameY,
            lessThan(dividerY),
            reason: 'the client name must render above the hairline',
          );
          expect(
            dividerY,
            lessThan(serviceY),
            reason: 'the service name must render below the hairline',
          );
          expect(
            dividerY,
            lessThan(priceY),
            reason: 'the price must render below the hairline',
          );

          // …and the CLIENT NAME leads row 1, with the range trailing it and
          // the dot hard right (SWAPPED 2026-07-24 — the range used to lead.
          // See `_buildCompactBody`'s row-1 comment for why the heavier
          // headline now comes before the lighter confirming metadata).
          //
          // Asserted on RENDERED GEOMETRY rather than on child index, so what
          // is pinned is the user-visible property — "the name sits left of
          // the time, and they do not overlap" — which survives any
          // re-wrapping of the row that preserves the painted order, and
          // fails the moment the painted order flips back.
          final Rect nameRect = tester.getRect(find.text(booking.clientName!));
          final Rect timeRect = tester.getRect(timeFinder);
          final Rect dotRect = tester.getRect(find.byType(TimelineStatusDot));
          expect(
            nameRect.left,
            lessThan(timeRect.left),
            reason:
                'the client name must LEAD row 1 — it rendered at '
                '${nameRect.left}dp against the range at ${timeRect.left}dp',
          );
          expect(
            timeRect.left - nameRect.right,
            closeTo(VelvetSpacing.xs + 2, 0.01),
            reason:
                'the name and the range must not overlap: the 6dp '
                '(VelvetSpacing.xs + 2) gap separating the identity headline '
                'from the trailing metadata measured '
                '${timeRect.left - nameRect.right}dp',
          );
          expect(
            dotRect.left - timeRect.right,
            closeTo(VelvetSpacing.xs, 0.01),
            reason:
                'the status dot stays hard right of the range, held against '
                'it by the tighter 4dp (VelvetSpacing.xs) gap so it reads as '
                'attached to this booking rather than floating on the margin',
          );
        },
      );
    },
  );

  // NEW IN THE MINIATURE PASS — the previous suite guarded WIDTH only.
  //
  // The compact layout is sized TO its box rather than measured after the
  // fact: at textScaler 1.0 a 54dp card leaves `54 − 3 (border 1.5 × 2) − 12
  // (`_compactPadding` vertical 6 × 2) = 39dp` of content, and the stack
  // spends all 39 —
  //
  //   row 1 (14, client name) + gap (4) + hairline (1) + gap (4)
  //   + row 2 (16, the price pill: a 14dp line box + 1dp padding × 2) = 39
  //
  // — with ZERO slack. That is the whole reason the pill's vertical padding
  // was cut 3 -> 1 (`_kCompactPriceVPad`): those 4dp bought the hairline and
  // its two gaps. A regression that restores the padding, widens a gap or
  // adds a row therefore OVERFLOWS the slot instead of silently eating room
  // that was never there, and these cases are what make that visible.
  //
  // FONT-SIZE PASS (2026-08-15) — was 41dp of content in a 56dp box; see
  // `velvet_text.dart`'s `masterCardClientName` doc. The arithmetic above is
  // the CURRENT (post-pass) figures.
  group('the 39dp vertical budget — the compact card fits its 54dp slot', () {
    testWidgets(
      'the natural height is EXACTLY MasterBookingCard.estimatedNaturalHeight '
      '(54dp) at textScaler 1.0',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(id: 'height-budget');

        // `Center` loosens the tight full-screen constraints `MaterialApp.home`
        // would otherwise impose — see the R2 group's first test for the full
        // explanation. Without it `getSize` reports the 800×600 test surface's
        // height, not the card's real content-driven height.
        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        final double height = tester
            .getSize(find.byKey(const Key('master-booking-card-height-budget')))
            .height;

        expect(
          height,
          MasterBookingCard.estimatedNaturalHeight,
          reason:
              'MasterBookingCard rendered at ${height}dp against a documented '
              '${MasterBookingCard.estimatedNaturalHeight}dp. Unlike the '
              'outgoing layout this is an EXACT figure, not an estimate with '
              'slack: the 39dp content budget is fully spent (see the group '
              'header). If this moved, either the layout grew — in which case '
              'a 30-minute card no longer fits its own ruled slot and '
              '_LaneColumn goes back to nudging cards off their hour line — '
              'or it shrank, in which case estimatedNaturalHeight and its '
              'derivation comment are now lying to bookings_timeline_grid.',
        );
      },
    );

    // The vertical fit, asserted the way the timeline actually applies it: a
    // real `minHeight: estimatedNaturalHeight` (54dp, was 56dp before the
    // 2026-08-15 font-size pass) floor. If the content out-measured the box
    // the card would grow PAST it (minHeight is a floor, never a ceiling —
    // see the widget's class doc), so an exact-fit result is a direct proof
    // of fit, not an approximation of one.
    for (final double lane in <double>[226, 266, 272]) {
      for (final ({
            String label,
            double price,
            double? priceMax,
            BookingStatus status,
          })
          shape
          in <
            ({
              String label,
              double price,
              double? priceMax,
              BookingStatus status,
            })
          >[
            (
              label: 'a single price',
              price: 450,
              priceMax: null,
              status: BookingStatus.confirmed,
            ),
            (
              label: 'a frozen RANGE band',
              price: 12500,
              priceMax: 25000,
              status: BookingStatus.confirmed,
            ),
            (
              label: 'a pathological 7-digit band',
              price: 1234567,
              priceMax: 8901234,
              status: BookingStatus.confirmed,
            ),
            (
              label: 'no price at all (CANCELLED)',
              price: 450,
              priceMax: null,
              status: BookingStatus.cancelled,
            ),
          ]) {
        testWidgets(
          '${shape.label} fits a ${MasterBookingCard.estimatedNaturalHeight.toInt()}dp '
          'box in the ${lane.toInt()}dp lane (textScaler 1.0)',
          (WidgetTester tester) async {
            final Booking booking =
                _shortBooking(
                  id: 'vfit',
                  durationMinutes: 30,
                  status: shape.status,
                ).copyWith(
                  serviceName:
                      'Комплексний догляд за волоссям з ботоксом та укладкою',
                  price: shape.price,
                  priceMax: shape.priceMax,
                );

            await tester.pumpApp(
              Center(
                child: SizedBox(
                  width: lane,
                  child: MasterBookingCard(
                    booking: booking,
                    onTap: () {},
                    minHeight: MasterBookingCard.estimatedNaturalHeight,
                  ),
                ),
              ),
            );
            await tester.pump();

            // `pumpApp` installs the overflow guard, so a RenderFlex overflow
            // in either row fails this on its own.
            expect(tester.takeException(), isNull);

            final double height = tester
                .getSize(find.byKey(const Key('master-booking-card-vfit')))
                .height;
            expect(
              height,
              MasterBookingCard.estimatedNaturalHeight,
              reason:
                  'the card grew to ${height}dp inside its '
                  '${MasterBookingCard.estimatedNaturalHeight}dp slot — the '
                  'content out-measures the 39dp budget, so a 30-minute '
                  'booking now overhangs its own ruled hour line.',
            );

            // The hairline really is inside the box, not pushed past its
            // bottom edge — a Column whose children out-measure their box
            // still LAYS OUT every child, so "the divider exists" alone
            // would not have caught an overflow.
            final Rect card = tester.getRect(
              find.byKey(const Key('master-booking-card-vfit')),
            );
            final Rect divider = tester.getRect(
              find.byKey(const Key('master-booking-card-compact-divider-vfit')),
            );
            expect(divider.top, greaterThan(card.top));
            expect(divider.bottom, lessThan(card.bottom));
          },
        );
      }
    }

    testWidgets(
      'above textScaler 1.0 the card GROWS rather than clipping — minHeight '
      'is a floor, never a ceiling',
      (WidgetTester tester) async {
        // Measured naturals: 54.0 / 58.0 / 62.0 at 1.0 / 1.15 / 1.3 (was
        // 56.0 / 60.0 / 65.0 before the 2026-08-15 font-size pass — see
        // `master_booking_card.dart`'s `estimatedNaturalHeight` doc). The
        // natural is a scale-1.0 budget by construction (the type scales,
        // the ruler does not), so the correct behaviour above 1.0 is a
        // taller card, exactly as the outgoing layout did.
        double previous = 0;
        for (final double scale in <double>[1.0, 1.15, 1.3]) {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: _shortBooking(id: 'vgrow'),
                  onTap: () {},
                  minHeight: MasterBookingCard.estimatedNaturalHeight,
                ),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          final double height = tester
              .getSize(find.byKey(const Key('master-booking-card-vgrow')))
              .height;
          expect(
            height,
            greaterThanOrEqualTo(MasterBookingCard.estimatedNaturalHeight),
            reason: 'the floor must always hold at textScaler $scale',
          );
          expect(
            height,
            greaterThan(previous),
            reason:
                'the card measured ${height}dp at textScaler $scale, no '
                'taller than the previous scale — the content is NOT tracking '
                'the text scaler, which means something in the stack has been '
                'frozen to a scale-1.0 constant (the price pill\'s zero-width '
                'height anchor is the usual suspect; see _PriceTag).',
          );
          previous = height;
        }
      },
    );
  });

  group('tap', () {
    testWidgets('onTap fires once per tap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpApp(
        MasterBookingCard(booking: _shortBooking(), onTap: () => taps++),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('master-booking-card-short-card')));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('cancelled booking hides the price', () {
    testWidgets(
      'a CANCELLED booking renders no price tag but still shows the status '
      'dot, and its transaction row is the service name alone',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(
          id: 'cancelled-card',
          status: BookingStatus.cancelled,
        );

        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(find.text('450 ₴'), findsNothing);
        expect(find.byType(TimelineStatusDot), findsOneWidget);
        expect(find.text(booking.serviceName), findsOneWidget);

        // No price means no pill at all — the compact layout's ONLY
        // `NeumorphicInset` is the price tag now that the badge is a bare
        // dot, so its total absence is a direct read of the `showsPrice`
        // gate rather than an indirect one.
        expect(
          find.descendant(
            of: find.byType(MasterBookingCard),
            matching: find.byType(NeumorphicInset),
          ),
          findsNothing,
        );

        // The service name takes the whole transaction row when there is no
        // price to share it with.
        final Rect card = tester.getRect(
          find.byKey(const Key('master-booking-card-cancelled-card')),
        );
        final Rect service = tester.getRect(find.text(booking.serviceName));
        expect(
          card.right - service.right,
          lessThan(VelvetSpacing.sm + 4),
          reason:
              'the service name stopped ${card.right - service.right}dp short '
              'of the card edge — something is still reserving the price '
              'column on a booking that owes nothing',
        );
      },
    );

    // THE FULL LAYOUT'S `else` ARM (2026-07-21 re-audit) — row 3's no-price
    // branch is the ONE arm the narrow-lane fix rewrote that nothing pinned.
    //
    // The fix turned row 3 from `_PriceTag` + `Spacer` + badge into
    // `Expanded(Align(centerLeft, _PriceTag))` + badge, and the `else` arm
    // kept a bare `Spacer()` so the badge stays hard right when there is no
    // price. That arm cannot OVERFLOW (a `Spacer` and a badge always fit), so
    // `pumpApp`'s guard is blind to it — and a "simplification" that dropped
    // the `Spacer` (leaving the badge to fall to the LEFT edge, under the
    // service name, where the price used to be) would look plausible in a
    // diff, break the layout on every cancelled/declined/missed card, and
    // pass every other test in this file. Hence a positional assertion, not
    // just a presence one. UNCHANGED by the miniature pass: the full layout
    // was deliberately not touched.
    testWidgets(
      'a CANCELLED booking in the FULL layout keeps its status badge hard '
      'right — the no-price arm must not lose its Spacer',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(
          id: 'cancelled-full-card',
          durationMinutes: 60,
          status: BookingStatus.cancelled,
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                // A 60-minute booking's floor (ADDENDUM 8: 60/60 * 120 =
                // 120), just past the 115dp full-layout switch.
                minHeight: 120,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(
            const Key('master-booking-card-divider-cancelled-full-card'),
          ),
          findsOneWidget,
          reason: 'precondition: this must be the FULL layout',
        );
        expect(find.text('450 ₴'), findsNothing);

        // `_fullPadding` is `EdgeInsets.all(VelvetSpacing.md)` (16), plus the
        // card's 1dp border — so a right-aligned badge sits ~17dp in from the
        // card's own right edge. A badge that lost its `Spacer` would start
        // at the LEFT padding instead, tens of dp away.
        final Rect card = tester.getRect(
          find.byKey(const Key('master-booking-card-cancelled-full-card')),
        );
        final Rect badge = tester.getRect(find.byType(TimelineStatusBadge));
        expect(
          card.right - badge.right,
          lessThan(VelvetSpacing.md + 2),
          reason:
              'the badge right edge sat ${card.right - badge.right}dp in from '
              'the card edge — row 3 has lost the Spacer that keeps it right-'
              'aligned when there is no price to occupy the Expanded',
        );
        expect(
          badge.left - card.left,
          greaterThan(VelvetSpacing.md + 2),
          reason:
              'the badge is hugging the LEFT padding, i.e. it collapsed into '
              'the slot the price would have used',
        );
      },
    );
  });

  // THE STATUS DOT (miniature pass, 2026-07-21) — the compact card's status
  // indicator, and the one element of this pass that DELETES information from
  // the visual channel. Everything below exists to prove it was compressed
  // rather than lost.
  group('TimelineStatusDot', () {
    testWidgets(
      'the compact layout draws a dot and the full layout draws the labelled '
      'badge — never both, never neither',
      (WidgetTester tester) async {
        for (final ({String label, double minHeight, int duration}) layout
            in <({String label, double minHeight, int duration})>[
              (label: 'compact', minHeight: 56, duration: 30),
              (label: 'full', minHeight: 120, duration: 60),
            ]) {
          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: _shortBooking(
                  id: 'dot-${layout.label}',
                  durationMinutes: layout.duration,
                ),
                onTap: () {},
                minHeight: layout.minHeight,
              ),
            ),
          );
          await tester.pump();

          final bool compact = layout.label == 'compact';
          expect(
            find.byType(TimelineStatusDot),
            compact ? findsOneWidget : findsNothing,
            reason: '${layout.label}: wrong status indicator',
          );
          expect(
            find.byType(TimelineStatusBadge),
            compact ? findsNothing : findsOneWidget,
            reason: '${layout.label}: wrong status indicator',
          );
        }
      },
    );

    testWidgets('the dot is TimelineStatusDot.diameter square', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: MasterBookingCard(
            booking: _shortBooking(id: 'dot-size'),
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      // `VelvetSpacing.sm` — one token up from the 6dp dot inside
      // `TimelineStatusBadge`, because stripping the label makes this dot
      // carry the whole signal. Asserted against the token rather than the
      // widget's own constant so a silent retune to a magic number fails.
      expect(TimelineStatusDot.diameter, VelvetSpacing.sm);
      expect(
        tester.getSize(find.byType(TimelineStatusDot)),
        const Size(VelvetSpacing.sm, VelvetSpacing.sm),
      );
    });

    // ONE SOURCE OF TRUTH — the dot and the badge must agree, for every
    // status, on both colour and label. `_timelineStatusVisual` (private to
    // `master_booking_card.dart`) is what guarantees it; this sweeps all six
    // statuses against `BookingStatusVisual.of` — the shared factory in
    // `booking_status_badge.dart` — so a fork in either indicator fails here
    // rather than shipping a card whose colour and whose tooltip disagree.
    for (final BookingStatus status in BookingStatus.values) {
      testWidgets(
        'the dot renders BookingStatusVisual.of(...).accent for ${status.name}',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking(
            id: 'dot-${status.name}',
            status: status,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          );
          await tester.pump();

          final BookingStatusVisual expected = BookingStatusVisual.of(
            booking,
            AppLocalizations.of(tester.element(find.byType(MasterBookingCard))),
          );

          final BoxDecoration decoration =
              tester
                      .widget<DecoratedBox>(
                        find.descendant(
                          of: find.byType(TimelineStatusDot),
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .decoration
                  as BoxDecoration;

          expect(decoration.color, expected.accent);
          expect(
            decoration.shape,
            BoxShape.circle,
            reason: 'the indicator must be a circle, not a square swatch',
          );
          // Impeller-GLES rasterizes `BoxShape.circle` + `boxShadow` as a hard
          // white square (`impeller_circle_shadow_guard_test.dart`). This dot
          // is one more circle that must never acquire one.
          expect(decoration.boxShadow, isNull);
        },
      );
    }

    // COLOUR IS NOT A SIGNAL — there are six statuses and three of their
    // accents are warm browns a step apart, so an 8dp swatch cannot carry the
    // status on its own. The label is COMPRESSED into the non-visual channel,
    // not dropped: this asserts both halves of that channel, for every
    // status, against the SAME localized strings the labelled badge renders.
    for (final BookingStatus status in BookingStatus.values) {
      testWidgets(
        'the dot announces the ${status.name} label to assistive tech and to '
        'a tooltip',
        (WidgetTester tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final Booking booking = _shortBooking(
            id: 'a11y-${status.name}',
            status: status,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          );
          await tester.pump();

          final AppLocalizations l10n = AppLocalizations.of(
            tester.element(find.byType(MasterBookingCard)),
          );
          final BookingStatusVisual expected = BookingStatusVisual.of(
            booking,
            l10n,
          );

          // The TOOLTIP — the sighted long-press/hover path. Derived from the
          // shared factory, never a literal (the `forbid_cyrillic_finder` gate
          // aside, a literal here would be a second source of truth for the
          // very string this pass is trying to keep single-sourced).
          final Tooltip tooltip = tester.widget<Tooltip>(
            find.descendant(
              of: find.byType(TimelineStatusDot),
              matching: find.byType(Tooltip),
            ),
          );
          expect(tooltip.message, expected.label);

          // The SEMANTICS label — identical to what `TimelineStatusBadge`
          // announces (`l10n.bookingStatusSemantics(label)`), so the two
          // indicators are indistinguishable to a screen reader even though
          // one of them draws no text at all.
          final SemanticsNode node = tester.getSemantics(
            find.descendant(
              of: find.byType(TimelineStatusDot),
              matching: find.byType(Semantics).last,
            ),
          );
          expect(
            node.label,
            contains(l10n.bookingStatusSemantics(expected.label)),
          );
          handle.dispose();
        },
      );
    }
  });

  group('mobile-perf MEDIUM-4/LOW-5 (2026-07-20) — decoration objects are '
      'hoisted, not reallocated per press', () {
    testWidgets(
      'the card outer decoration is the SAME object instance across a '
      'press/release cycle — a regression that reintroduces per-build '
      'BoxDecoration/Border.all allocation would still LOOK correct but '
      'fail this identity check',
      (WidgetTester tester) async {
        const Key cardKey = Key('master-booking-card-decoration-card');
        final Booking booking = _shortBooking(id: 'decoration-card');

        await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
        await tester.pump();

        // `.first`, not a bare (implicitly `.single`) match: the price tag's
        // `NeumorphicInset` builds its own `AnimatedContainer` internally, so
        // the compact card contains two. (Before the miniature pass it held
        // three — the status badge's inset was the third; the dot it became
        // is a plain `DecoratedBox`.) Pre-order descendant traversal visits
        // the CARD's own outer `AnimatedContainer` — the one this identity
        // check is about — first, so `.first` is unambiguous.
        AnimatedContainer cardContainer() => tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byKey(cardKey),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );

        final Decoration unpressedCard1 = cardContainer().decoration!;

        final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byKey(cardKey)),
        );
        await tester.pump();

        // Pressed and unpressed are deliberately two DIFFERENT static
        // instances (`_decorationPressed`/`_decorationUnpressed`) — this
        // asserts the SWITCH still happens, not that the decoration is
        // frozen forever.
        final Decoration pressedCard = cardContainer().decoration!;
        expect(pressedCard, isNot(same(unpressedCard1)));

        await gesture.up();
        await tester.pump();

        final Decoration unpressedCard2 = cardContainer().decoration!;
        expect(
          unpressedCard2,
          same(unpressedCard1),
          reason:
              'releasing back to the unpressed state must reuse the exact '
              'same hoisted BoxDecoration object, not allocate a fresh '
              '(value-equal but distinct) one',
        );
      },
    );

    // Design-parity finding #9: the price tag is a `NeumorphicInset` recessed
    // well (transcribed from the approved design's own `PriceTag`), not a
    // hoisted-`BoxDecoration` bordered pill — so it has no stable decoration-
    // object identity to pin (`NeumorphicInset` builds a fresh `BoxDecoration`
    // per rebuild, same as every other call site of that shared widget across
    // the app). This structural check replaces the retired identity
    // assertions above: the price tag renders through `NeumorphicInset`, on
    // every press/release frame, without exception.
    testWidgets(
      'the price tag renders as a NeumorphicInset well, before and after a '
      'press',
      (WidgetTester tester) async {
        const Key cardKey = Key('master-booking-card-neumorphic-price');
        final Booking booking = _shortBooking(id: 'neumorphic-price');

        await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
        await tester.pump();

        Finder priceInset() => find.ancestor(
          of: find.text('450 ₴'),
          matching: find.byType(NeumorphicInset),
        );

        expect(priceInset(), findsOneWidget);

        final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byKey(cardKey)),
        );
        await tester.pump();
        expect(priceInset(), findsOneWidget);

        await gesture.up();
        await tester.pump();
        expect(priceInset(), findsOneWidget);
      },
    );
  });

  // `_PriceTag.verticalPadding` (miniature pass) — the 4dp that bought the
  // compact card's hairline and its two gaps, and the guarantee that the
  // >=1h card did NOT pay for them.
  group('the price pill\'s per-layout vertical padding', () {
    testWidgets(
      'the compact pill is exactly 4dp shorter than the full one, and the '
      'full one is unchanged at its design height',
      (WidgetTester tester) async {
        Future<double> pillHeight(double minHeight, int duration) async {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 272,
                child: MasterBookingCard(
                  booking: _shortBooking(
                    id: 'pillpad',
                    durationMinutes: duration,
                  ),
                  onTap: () {},
                  minHeight: minHeight,
                ),
              ),
            ),
          );
          await tester.pump();
          return tester
              .renderObject<RenderBox>(
                find.ancestor(
                  of: find.text('450 ₴'),
                  matching: find.byType(NeumorphicInset),
                ),
              )
              .size
              .height;
        }

        final double compact = await pillHeight(54, 30);
        final double full = await pillHeight(120, 60);

        // FONT-SIZE PASS (2026-08-15) — both figures dropped 1dp (21 -> 20,
        // 17 -> 16): `master_booking_card.dart`'s two `PriceTag` call sites
        // now both pass `VelvetText.masterCardPricePill` (10.2 sp, a 14dp
        // line box) instead of the shared `pill()` (11 sp, 15dp) — see that
        // token's doc for why a NEW card-scoped token was needed rather than
        // shrinking `pill()` itself (shared with wish-list/passport, out of
        // scope). The PADDING split this test exists to pin is UNCHANGED:
        // `_PriceTag.verticalPadding` still defaults to 3 for the full layout
        // and 1 for the compact one, so the two pills still differ by exactly
        // 4dp — that invariant survives the font-size pass untouched, only
        // the absolute numbers moved.
        expect(
          full,
          20,
          reason:
              'the FULL layout\'s price pill measured ${full}dp — it must '
              'stay at 20dp (14dp line + 3dp padding × 2, using '
              'VelvetText.masterCardPricePill). The compact layout\'s padding '
              'cut must not have leaked into the shared default.',
        );
        expect(
          compact,
          16,
          reason:
              'the COMPACT pill measured ${compact}dp — the 1dp padding is '
              'what pays for the hairline and its two gaps inside the 39dp '
              'budget.',
        );
        expect(full - compact, 4);
      },
    );
  });

  group('mobile-qa INFO (2026-08-15) — row 3\'s max(price pill, badge) stays '
      'price-pill-driven after the badge label was restored to 9.0sp', () {
    testWidgets(
      'TimelineStatusBadge (row-3 verticalPadding: 3) renders strictly '
      'shorter than the FULL layout\'s price pill, so the price pill — not '
      'the badge — is still what sets row 3\'s height',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 272,
              child: MasterBookingCard(
                booking: _shortBooking(
                  id: 'badge-vs-pill',
                  durationMinutes: 60,
                ),
                onTap: () {},
                minHeight: 120,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        final double badgeHeight = tester
            .getSize(find.byType(TimelineStatusBadge))
            .height;
        final double pillHeight = tester
            .renderObject<RenderBox>(
              find.ancestor(
                of: find.text('450 ₴'),
                matching: find.byType(NeumorphicInset),
              ),
            )
            .size
            .height;

        // Measured directly (`tester.getSize`/`renderObject`), matching
        // `velvet_text.dart`'s `masterCardBadgeLabel` doc comment exactly:
        // 16.0dp badge vs 20.0dp price pill at textScaler 1.0. Pinning both
        // numbers, not just the inequality, so a future badge-size bump
        // that DOES cross the pill's height fails loudly here instead of
        // silently moving `MasterBookingCard.fullLayoutNaturalHeight`.
        expect(
          badgeHeight,
          16.0,
          reason:
              'TimelineStatusBadge measured ${badgeHeight}dp at 9.0sp — if '
              'this moved, row 3\'s max() may no longer be the price pill.',
        );
        expect(pillHeight, 20.0);
        expect(
          badgeHeight,
          lessThan(pillHeight),
          reason:
              'row 3 is max(price pill, badge) — the badge must stay '
              'strictly under the price pill\'s height, or a badge-size '
              'bump silently becomes what sets MasterBookingCard.'
              'fullLayoutNaturalHeight instead of the price pill.',
        );
      },
    );
  });

  group('guest booking (no client name)', () {
    testWidgets('falls back to the localized guest label, still compact', (
      WidgetTester tester,
    ) async {
      // The same pinned Kyiv wall-clock instant `_shortBooking` uses — see its
      // doc for why this file's fixtures are inert with respect to "now".
      // Hand-built here only because this case needs a null client name, which
      // the shared factory does not expose.
      // future-date-ok: pinned Kyiv wall-clock fixture.
      final DateTime startAt = DateTime.utc(2026, 7, 20, 6);
      final Booking booking = Booking(
        id: 'guest-card',
        masterId: 'master-1',
        masterFirstName: 'Оля',
        masterLastName: 'Коваль',
        masterType: 'INDEPENDENT_MASTER',
        clientFirstName: null,
        clientLastName: null,
        serviceId: 'service-1',
        serviceName: 'Стрижка жіноча',
        durationMinutes: 20,
        price: 450,
        startAt: startAt,
        endAt: startAt.add(const Duration(minutes: 20)),
        status: BookingStatus.confirmed,
        canReview: false,
      );

      // See the R2 group's first test for why `Center` is required to
      // measure the card's real content-driven height under this harness.
      await tester.pumpApp(
        Center(
          child: MasterBookingCard(booking: booking, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('master-booking-card-guest-card')),
        findsOneWidget,
      );
      // The guest label is SHORTER than a real name, so it can only ever make
      // row 1 narrower — the height is the same 39dp/54dp budget.
      final double height = tester
          .getSize(find.byKey(const Key('master-booking-card-guest-card')))
          .height;
      expect(height, MasterBookingCard.estimatedNaturalHeight);
    });
  });

  group('mobile-perf LOW fix (Phase 231) — _fullBodyContent cache keys on '
      'clientName, not just Booking', () {
    testWidgets(
      'a guest booking\'s cached FULL body re-renders the new locale\'s '
      'fallback label after a locale change, instead of keeping the stale '
      'cached widget',
      (WidgetTester tester) async {
        // See `_shortBooking`'s doc for why a fixed instant is required here.
        // future-date-ok: pinned Kyiv wall-clock fixture.
        final DateTime startAt = DateTime.utc(2026, 7, 20, 6);
        final Booking guestBooking = Booking(
          id: 'guest-locale-cache',
          masterId: 'master-1',
          masterFirstName: 'Оля',
          masterLastName: 'Коваль',
          masterType: 'INDEPENDENT_MASTER',
          clientFirstName: null,
          clientLastName: null,
          serviceId: 'service-1',
          serviceName: 'Стрижка жіноча',
          durationMinutes: 60,
          price: 450,
          startAt: startAt,
          endAt: startAt.add(const Duration(minutes: 60)),
          status: BookingStatus.confirmed,
          canReview: false,
        );

        // minHeight: 120 forces the FULL body (`_fullBodyContent`'s cache
        // only exists on this layout) — same floor the badge-vs-pill test
        // above uses.
        Widget buildCard() => Center(
          child: SizedBox(
            width: 272,
            child: MasterBookingCard(
              booking: guestBooking,
              onTap: () {},
              minHeight: 120,
            ),
          ),
        );

        await tester.pumpApp(buildCard(), locale: const Locale('uk'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        // i18n-finder-ok: this test's whole point is pinning the UK-locale
        // guest fallback string itself, not incidental UI copy.
        expect(find.text('Гість'), findsOneWidget);
        expect(find.text('Guest'), findsNothing);

        // Re-pump the SAME Booking (value-equal) under a DIFFERENT locale.
        // `MasterBookingCard` carries no explicit key here, so Flutter's
        // element diffing preserves the existing `_MasterBookingCardState`
        // — and with it `_fullBodyContentCache` — across this rebuild,
        // exactly reproducing the auditor's repro: an unchanged `Booking`
        // with a changed `clientName` fallback.
        await tester.pumpApp(buildCard(), locale: const Locale('en'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(
          find.text('Guest'),
          findsOneWidget,
          reason:
              'the FULL body\'s _fullBodyContent cache keyed on Booking '
              'alone, so it returned the stale cached widget still '
              'printing the uk fallback ("Гість") after the locale '
              'changed to en. The cache guard must also key on '
              'clientName.',
        );
        // i18n-finder-ok: asserting the stale UK fallback is GONE after the
        // locale change — the reproduction this test pins.
        expect(find.text('Гість'), findsNothing);
      },
    );
  });

  group(
    'adaptive full/compact layout (2026-07-20 design-parity pass) — the '
    'switch reads the resolved minHeight constraint, not durationMinutes',
    () {
      testWidgets(
        'a >=115dp card (a 60-minute booking\'s 120dp floor) renders the FULL '
        'layout: client name, a divider, the service name BELOW the '
        'divider, the start–end time range (NO date), price and status — all '
        'present, none clipped',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking(
            id: 'full-card',
            durationMinutes: 60,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 120,
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);

          expect(find.text(booking.clientName!), findsOneWidget);
          expect(
            find.byKey(const Key('master-booking-card-divider-full-card')),
            findsOneWidget,
          );
          // …and NOT the compact layout's own hairline. Both bodies now carry
          // one, so the layout probe has to name which.
          expect(
            find.byKey(
              const Key('master-booking-card-compact-divider-full-card'),
            ),
            findsNothing,
          );
          expect(find.text(booking.serviceName), findsOneWidget);
          // The full layout's `schedule_outlined` caption is the SAME
          // start–end range the compact grid prints — exactly once, and
          // date-free.
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
          _expectNoDateOnCard(booking);
          // The bare start time alone must NOT be printed anywhere.
          expect(find.text(formatSlotTime(booking.startAt)), findsNothing);
          expect(find.text('450 ₴'), findsOneWidget);
          // The FULL layout keeps the LABELLED badge — the dot is compact-only.
          expect(find.byType(TimelineStatusBadge), findsOneWidget);
          expect(find.byType(TimelineStatusDot), findsNothing);

          // Structural proof the service row sits BELOW the divider (the
          // design's canonical shape), not on the client-identity row: the
          // divider's top must sit strictly between the client name's top
          // and the service row's top.
          final double clientNameY = tester
              .getTopLeft(find.text(booking.clientName!))
              .dy;
          final double dividerY = tester
              .getTopLeft(
                find.byKey(const Key('master-booking-card-divider-full-card')),
              )
              .dy;
          final double serviceY = tester
              .getTopLeft(find.text(booking.serviceName))
              .dy;
          expect(
            clientNameY,
            lessThan(dividerY),
            reason: 'the client name must render above the divider',
          );
          expect(
            dividerY,
            lessThan(serviceY),
            reason: 'the service name must render below the divider',
          );
        },
      );

      testWidgets(
        'a ${MasterBookingCard.microLayoutMaxHeight.toInt()}dp card (the '
        'exclusive micro/compact boundary) stays on the COMPACT grid — its '
        'own hairline, a status dot, no date — and still renders every '
        'field un-clipped',
        (WidgetTester tester) async {
          // ADDENDUM 8: `MasterBookingCard.microLayoutMaxHeight` (54dp, was
          // 56dp before the 2026-08-15 font-size pass — see
          // `velvet_text.dart`'s `masterCardClientName` doc) is no longer
          // the grid's card FLOOR (that is now `microLayoutNaturalHeight`,
          // 27dp) — it is the MICRO/COMPACT BOUNDARY, and the bound is
          // exclusive, so a card handed exactly that value still gets the
          // compact grid. At 120dp/hour that is a 27-minute booking. The
          // fixture's own `durationMinutes` is irrelevant to the switch by
          // design — `_layout` reads `minHeight`, never the duration —
          // which is precisely what this case pins.
          final Booking booking = _shortBooking(
            id: 'compact-floor-card',
            durationMinutes: 15,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: MasterBookingCard.microLayoutMaxHeight,
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);

          // The compact-only shape: its own hairline key, NOT the full
          // layout's, a dot rather than a pill, and — like the full layout —
          // no date.
          expect(
            find.byKey(
              const Key('master-booking-card-divider-compact-floor-card'),
            ),
            findsNothing,
          );
          expect(
            find.byKey(
              const Key(
                'master-booking-card-compact-divider-compact-floor-card',
              ),
            ),
            findsOneWidget,
          );
          expect(find.byType(TimelineStatusDot), findsOneWidget);
          expect(find.byType(TimelineStatusBadge), findsNothing);
          _expectNoDateOnCard(booking);

          // Every field the compact grid DOES show is still there.
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          expect(find.text(booking.serviceName), findsOneWidget);
          expect(find.text(booking.clientName!), findsOneWidget);
          expect(find.text('450 ₴'), findsOneWidget);

          final double height = tester
              .getSize(
                find.byKey(const Key('master-booking-card-compact-floor-card')),
              )
              .height;
          expect(height, closeTo(MasterBookingCard.microLayoutMaxHeight, 0.5));
        },
      );

      testWidgets(
        'MUTATION CHECK — forcing the compact layout at every height makes '
        'the full-layout divider assertion fail; the real code must NOT '
        'exhibit this failure',
        (WidgetTester tester) async {
          // This test intentionally re-runs the FIRST test's own divider
          // assertion against a card whose `minHeight` is comfortably past
          // the >=115dp threshold, as a standing structural guard: it is
          // the automated half of the manual mutation check documented in
          // the phase report (temporarily hardcoding `_useFullLayout` to
          // always return `false` in `master_booking_card.dart` and
          // re-running this file turns
          // THIS test red — the full divider key never renders — while every
          // other test in this file stays green, isolating the switch as
          // the thing under test).
          final Booking booking = _shortBooking(
            id: 'mutation-guard-card',
            durationMinutes: 90,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 252,
              ),
            ),
          );
          await tester.pump();

          expect(
            find.byKey(
              const Key('master-booking-card-divider-mutation-guard-card'),
            ),
            findsOneWidget,
            reason:
                'a 252dp (90-minute) card must select the FULL layout — if '
                'this fails, the height-vs-threshold switch in '
                'MasterBookingCard.build has regressed to always picking '
                'the compact body.',
          );
          expect(find.byType(TimelineStatusBadge), findsOneWidget);
        },
      );
    },
  );

  // THE LAYOUT THRESHOLD IS A dp FIGURE, NOT A DURATION — the lesson this
  // group now records, having been rewritten twice for the same reason.
  //
  // It shipped as "the 45-minute question — why 45 minutes stays COMPACT"
  // (scale 112, floor 84dp). ADDENDUM 7 raised the scale to 168 and it became
  // "why 45 minutes NOW gets the FULL layout" (floor 126dp). ADDENDUM 8
  // dropped the scale to 120 and it is compact again (floor 90dp). The
  // THRESHOLD held through all three: `_kFullLayoutMinHeight` is, and has
  // always been, `fullLayoutNaturalHeight` — a card gets the fuller shape
  // precisely when its floor can contain that body. Only the arithmetic from
  // duration to floor changed.
  //
  // IT HAS SINCE MOVED, and for the one reason that can move it: the BODY
  // grew. The ROW-1 GLYPH pass (2026-07-24) gave the full card's client-name
  // row a leading 16dp `person_outlined` icon against a 15dp line box, so the
  // natural went 117 -> 118dp and the threshold with it. That is the contract
  // working, not breaking — the constant tracks a measurement, so it is the
  // CONTENT that must be re-measured after a density change, never the
  // threshold that gets retuned to keep a duration on the right side.
  //
  // MOVED AGAIN, 2026-08-15: the font-size pass (see `velvet_text.dart`'s
  // `masterCardClientName` doc) shrank every OTHER row of the full body while
  // row 1 stayed glyph-pinned at 16dp, taking the natural (and the threshold)
  // 118 -> 115. Same contract, same reason — re-measured, not retuned. See
  // `master_booking_card.dart`'s `fullLayoutNaturalHeight` doc for the full
  // derivation.
  //
  // So the cases below are written against FLOORS, and each states the
  // duration that produces it at the CURRENT scale as a derived aside. The
  // boundary cases (117 / 118, historical — now 114 / 115) are the real
  // guard and are scale-free.
  //
  // `_buildFullBody`'s NATURAL height, measured with the worst realistic
  // content (a long service name and a frozen RANGE band) at the narrowest
  // production lane, is 115.0dp @1.0 (120 @1.15, 126 @1.3 — was 118.0 / 124 /
  // 132 before the 2026-08-15 pass; unchanged BY THAT PASS by the glyph,
  // which does not scale with `textScaler`) — pinned exactly by the "the
  // FULL body still measures exactly …dp" group below. At 120dp/hour an
  // hour-long card's 120dp band is 5dp clear of that natural (was 2dp), so at
  // the app's 1.3 text-scale ceiling its body (126dp) grows ~6dp past the
  // band; nothing clips (content always wins) and that overhang is the reason
  // `_kHourH` must not drop below 120.
  // THE MICRO LAYOUT (ADDENDUM 8, 2026-07-24) — the third density.
  //
  // `bookings_timeline_grid.dart` dropped `_kHourH` to 120, which puts a
  // 15-minute booking in a 30dp band. The compact grid needs 54dp (was 56dp
  // before the 2026-08-15 font-size pass), so without
  // a third shape every short booking would have been inflated to a box
  // roughly twice its own wall-clock footprint — the overrun the scale change
  // exists to remove. The micro body is ONE row: service name (flexes) · time
  // range · status dot.
  //
  // What this group has to prove, beyond "it renders": that the dropped
  // fields (client name, price) were COMPRESSED into the a11y channel rather
  // than lost, and that a `null` minHeight — every caller outside the
  // timeline — still gets the COMPACT grid rather than falling through to
  // micro on a `?? 0`.
  group('the MICRO layout (< 54dp floors)', () {
    testWidgets(
      'a 30dp card (15 minutes at 120dp/hour) renders the micro row: service '
      'name, time range and the status dot — no client name, no price pill, '
      'no hairline of either layout',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(
          id: 'micro-card',
          durationMinutes: 15,
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 30,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        // Present.
        expect(find.text(booking.serviceName), findsOneWidget);
        expect(
          find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
          findsOneWidget,
        );
        expect(find.byType(TimelineStatusDot), findsOneWidget);

        // Absent — and each for a different reason, so each is asserted
        // separately rather than as one "it's smaller" claim.
        expect(
          find.text(booking.clientName!),
          findsNothing,
          reason: 'the client name has no room in a single 13dp text row',
        );
        expect(
          find.text('450 ₴'),
          findsNothing,
          reason: 'the price pill alone is taller than the whole micro row',
        );
        expect(find.byType(TimelineStatusBadge), findsNothing);
        expect(
          find.byKey(const Key('master-booking-card-divider-micro-card')),
          findsNothing,
        );
        expect(
          find.byKey(
            const Key('master-booking-card-compact-divider-micro-card'),
          ),
          findsNothing,
          reason:
              'a hairline separates two rows; the micro body has only one, so '
              'a divider here means the compact grid rendered',
        );
        _expectNoDateOnCard(booking);
      },
    );

    testWidgets('the micro body measures exactly MasterBookingCard.'
        'microLayoutNaturalHeight (28dp) at textScaler 1.0 — the number '
        'BookingsTimelineGrid floors every card at', (
      WidgetTester tester,
    ) async {
      // Measured with a floor BELOW the natural so the content, not the
      // floor, decides the height. `_cardMinHeightFor` produces exactly this
      // shape for any booking under the 14.0-minute break-even.
      final Booking booking =
          _shortBooking(id: 'micro-natural', durationMinutes: 10).copyWith(
            // The worst realistic content: if the height were content-sensitive
            // at all, a long name plus a frozen band is what would expose it.
            serviceName:
                'Комплексний догляд за волоссям з ботоксом та укладкою',
            price: 12500,
            priceMax: 25000,
          );

      for (final double lane in <double>[226, 266, 272]) {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: lane,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 1,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          tester
              .getSize(
                find.byKey(
                  const Key(
                    'master-booking-card-'
                    'micro-natural',
                  ),
                ),
              )
              .height,
          closeTo(MasterBookingCard.microLayoutNaturalHeight, 0.01),
          reason:
              'at ${lane}dp of lane the micro card no longer measures '
              '${MasterBookingCard.microLayoutNaturalHeight}dp. That '
              'constant is BookingsTimelineGrid\'s card floor and '
              'occupiedHeightFor\'s prediction for every sub-break-even '
              'booking — re-measure and update both, do not widen this '
              'tolerance. A value that VARIES with lane width means a row '
              'is wrapping instead of ellipsising.',
        );
      }
    });

    testWidgets(
      'the dropped fields survive in the a11y channel: the client name stays '
      'in the Semantics label and the price moves to Semantics value',
      (WidgetTester tester) async {
        // Disposed INLINE at the end, not via `addTearDown`:
        // `WidgetTester._endOfTestVerifications` asserts no handle is live and
        // runs BEFORE tearDowns, so a tearDown-scheduled dispose fails.
        final SemanticsHandle handle = tester.ensureSemantics();

        final Booking booking = _shortBooking(
          id: 'micro-semantics',
          durationMinutes: 15,
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 30,
              ),
            ),
          ),
        );
        await tester.pump();

        final SemanticsNode node = tester.getSemantics(
          find.byKey(const Key('master-booking-card-micro-semantics')),
        );
        expect(
          node.label,
          contains(booking.clientName),
          reason:
              'the client name is invisible in the micro row, so the Semantics '
              'label is the ONLY channel a screen-reader user has for it',
        );
        expect(
          node.value,
          contains('450'),
          reason:
              'the price pill is dropped from the micro visual; it must be '
              'announced as the node value instead of disappearing',
        );

        handle.dispose();
      },
    );

    testWidgets(
      'the micro card is still one whole tap target that fires onTap',
      (WidgetTester tester) async {
        Booking? tapped;
        final Booking booking = _shortBooking(
          id: 'micro-tap',
          durationMinutes: 15,
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: booking,
                onTap: () => tapped = booking,
                minHeight: 30,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('master-booking-card-micro-tap')),
        );
        await tester.pump();

        expect(
          tapped?.id,
          'micro-tap',
          reason:
              'everything dropped from the micro visual is reachable only via '
              '«Деталі запису», so losing the tap loses the data outright',
        );
      },
    );

    testWidgets(
      'a NULL minHeight still selects the COMPACT grid, never micro — «no '
      'constraint» is not «a very tight constraint»',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(id: 'micro-null');

        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(
            const Key('master-booking-card-compact-divider-micro-null'),
          ),
          findsOneWidget,
          reason:
              'a `minHeight ?? 0` read would make 0 < 54 true and silently '
              're-shape every caller outside BookingsTimelineGrid',
        );
        expect(find.text(booking.clientName!), findsOneWidget);
      },
    );

    // The boundary, in both directions. 54 is EXCLUSIVE — a floor of exactly
    // the compact natural still gets the compact grid, because the compact
    // body fits in it. Was 56 (55.9 / 56) before the 2026-08-15 font-size
    // pass dropped `estimatedNaturalHeight` to 54 — see that constant's doc.
    for (final ({double minHeight, bool micro}) boundary
        in <({double minHeight, bool micro})>[
          (minHeight: 53.9, micro: true),
          (minHeight: 54, micro: false),
        ]) {
      testWidgets('minHeight ${boundary.minHeight} selects the '
          '${boundary.micro ? 'MICRO' : 'COMPACT'} layout', (
        WidgetTester tester,
      ) async {
        expect(
          MasterBookingCard.microLayoutMaxHeight,
          MasterBookingCard.estimatedNaturalHeight,
          reason:
              'the boundary IS the compact body\'s own natural height — a '
              'floor that cannot contain it is exactly what micro is for',
        );

        final Booking booking = _shortBooking(id: 'micro-boundary');
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: boundary.minHeight,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(
            const Key('master-booking-card-compact-divider-micro-boundary'),
          ),
          boundary.micro ? findsNothing : findsOneWidget,
        );
      });
    }
  });

  group('the full/compact threshold is a dp floor, not a duration', () {
    testWidgets(
      'a 90dp floor (45 minutes at 120dp/hour) selects the COMPACT grid — the '
      'floor cannot contain the full body\'s 115dp natural (was 118dp before '
      'the 2026-08-15 font-size pass)',
      (WidgetTester tester) async {
        final Booking booking =
            _shortBooking(id: 'forty-five', durationMinutes: 45).copyWith(
              serviceName:
                  'Комплексний догляд за волоссям з ботоксом та укладкою',
              price: 12500,
              priceMax: 25000,
            );

        // A 45-minute booking's real ADDENDUM 8 floor: 45/60 * 120 = 90dp.
        const double floor = 90;

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: floor,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        // The COMPACT layout's divider, NOT the full one.
        expect(
          find.byKey(const Key('master-booking-card-divider-forty-five')),
          findsNothing,
        );
        expect(
          find.byKey(
            const Key('master-booking-card-compact-divider-forty-five'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(find.byKey(const Key('master-booking-card-forty-five')))
              .height,
          closeTo(floor, 0.5),
          reason:
              'the 90dp floor must be met exactly — it exceeds the compact '
              'body\'s 54dp natural, so the floor (not the content) sizes the '
              'box and the card lands on its 45-minute end-time line.',
        );
      },
    );

    // The threshold's exact boundary is now 115 (== fullLayoutNaturalHeight,
    // down from 118 with the 2026-08-15 font-size pass — up from 117 before
    // that with the ROW-1 GLYPH pass), so a future off-by-one (>= vs >) or a
    // drift of the constant is a failure rather than a silently different
    // card.
    for (final ({double minHeight, bool full}) boundary
        in <({double minHeight, bool full})>[
          (minHeight: 114, full: false),
          (minHeight: 115, full: true),
        ]) {
      testWidgets('minHeight ${boundary.minHeight} selects the '
          '${boundary.full ? 'FULL' : 'COMPACT'} layout', (
        WidgetTester tester,
      ) async {
        expect(
          MasterBookingCard.fullLayoutMinHeight,
          115,
          reason:
              'fixture guard: the switch must be at 115 (the full body\'s own '
              'natural) or this boundary pair is measuring the wrong edge',
        );
        await tester.pumpApp(
          Center(
            child: MasterBookingCard(
              booking: _shortBooking(id: 'boundary', durationMinutes: 60),
              onTap: () {},
              minHeight: boundary.minHeight,
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('master-booking-card-divider-boundary')),
          boundary.full ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('master-booking-card-compact-divider-boundary')),
          boundary.full ? findsNothing : findsOneWidget,
        );
      });
    }
  });

  // The 2026-07-21 pass: both layouts print `start–end`, neither prints a
  // date. The per-layout content assertions live in the groups above; this
  // group pins the two properties those assertions cannot express — where the
  // end instant COMES FROM, and that the widened label cannot overflow the
  // narrowest lane the timeline ever renders.
  group('start–end time range', () {
    // THE MUTATION THIS CATCHES: `formatTimeRange(startAt, durationMinutes)`
    // substituted for `formatSlotTimeRange(startAt, endAt)`. Against a normal
    // fixture the two agree exactly, so every other test in this file would
    // stay green through that swap. Here `endAt` is deliberately 45 minutes
    // after the start while `durationMinutes` still says 20 — only a card
    // reading the real persisted `endAt` prints 09:45.
    for (final ({String label, double? minHeight}) layout
        in <({String label, double? minHeight})>[
          (label: 'compact', minHeight: null),
          (label: 'full', minHeight: 120),
        ]) {
      testWidgets('the ${layout.label} layout reads the persisted endAt, never '
          'startAt + durationMinutes', (WidgetTester tester) async {
        final Booking base = _shortBooking(id: 'endat-${layout.label}');
        final Booking booking = base.copyWith(
          endAt: base.startAt.add(const Duration(minutes: 45)),
        );
        expect(
          booking.durationMinutes,
          20,
          reason:
              'the fixture must keep a durationMinutes that DISAGREES with '
              'endAt, or this proves nothing',
        );

        await tester.pumpApp(
          Center(
            child: MasterBookingCard(
              booking: booking,
              onTap: () {},
              minHeight: layout.minHeight,
            ),
          ),
        );
        await tester.pump();

        // Precondition — the pumped card really is the layout named, now
        // that both bodies carry a hairline and print the same range string.
        expect(
          find.byKey(Key('master-booking-card-divider-endat-${layout.label}')),
          layout.label == 'full' ? findsOneWidget : findsNothing,
        );

        // 09:00 Kyiv + 45 minutes. Asserted through the formatter (not a
        // literal) so the expectation stays anchored to the fixture, then
        // cross-checked against the duration-derived string it must NOT be.
        expect(
          find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
          findsOneWidget,
        );
        expect(
          find.text(formatTimeRange(booking.startAt, booking.durationMinutes)),
          findsNothing,
          reason:
              're-deriving the end from durationMinutes is exactly the '
              'second source of truth this formatter choice avoids',
        );
      });
    }

    // OVERFLOW BUDGET — the range roughly DOUBLES the leading label it
    // replaced (measured through `VelvetText.masterCardTime`: «09:00» is
    // 30.45dp, «09:00–09:20» is 66.65dp at textScaler 1.0, and 39.55 -> 86.58
    // at 1.3), so this is the real risk of the change.
    //
    // RE-MEASURED after the ONE-TIME-STYLE pass (2026-07-24) put
    // `VelvetText.masterCardTime` on the FULL card's own recipe (11 sp rather
    // than 11.5): «09:00–09:20» is now 63.76dp at textScaler 1.0 and 82.86dp
    // at 1.3. Every figure moved in the SAFE direction — the label got
    // narrower, so the `Expanded` client name beside it GAINED ~4dp — but the
    // sweeps below are kept exactly as they were: they assert a usable
    // remaining column rather than an exact width, so they still bind, and a
    // future edit that widens the label back has something to fail against.
    //
    // WHAT THE MINIATURE PASS MOVED — this sweep now measures TWO shares
    // ---------------------------------------------------------------------
    // Before the pass, the range shared row 1 with an `Expanded` SERVICE name
    // and a non-flex price pill; the service name was the thing being
    // squeezed, so a single service-width floor per lane was the whole story.
    // The range now shares row 1 with the `Expanded` CLIENT NAME and an 8dp
    // dot, while the service name has moved to row 2 beside the price. Those
    // are two independent budgets, and pinning only one of them would leave
    // the other free to collapse — so each case asserts BOTH shares.
    //
    // Both flexing labels sit in an `Expanded`, i.e. a TIGHT width
    // constraint, so each `Text`'s render box reports the width the row
    // ALLOTTED it rather than its own intrinsic width. That is what makes
    // these measurements meaningful as budget floors.
    //
    // THE NARROWEST LANE IS 226dp, NOT 266 — a 320dp device, not a 360dp one
    // ---------------------------------------------------------------------
    // `bookings_timeline_grid.dart`'s "ADDENDUM 3" clamps the 272dp card to
    // `constraints.maxWidth`, and the lane area is `deviceWidth − 94` (24 + 24
    // screen padding, 42 ruler, 4 gap). An earlier version of this group
    // asserted 266dp — `360 − 94` — was "the narrowest lane the production
    // grid ever renders". It is not: this app treats 320dp as a supported
    // width throughout (`test/golden/helpers/golden_pump.dart`'s
    // `kGoldenWidths` is {320, 360, 414}; `service_setup_screen_test.dart`
    // sweeps {320, 360, 412}; `pricing_toggle_overflow_test.dart` exists
    // solely for 320dp), and minSdk 26 keeps 320dp Android 8 hardware in the
    // supported fleet. `320 − 94 = 226`, so 226dp is the real floor and the
    // clamp genuinely produces it.
    //
    // SWEPT ACROSS textScaler, and that sweep is load-bearing: 1.3 is the
    // app's own MediaQuery ceiling (`main.dart`), and the range's extra width
    // scales WITH the text while the lane does not — so the narrowest lane at
    // the largest scale is the corner the widened label actually threatens.
    // `pumpApp` installs the overflow guard, so a RenderFlex overflow fails
    // these on its own.
    for (final double lane in <double>[226, 266, 272]) {
      for (final double scale in <double>[1.0, 1.15, 1.3]) {
        testWidgets(
          'the range, the client name and the service name all keep a usable '
          'share in the ${lane.toInt()}dp lane (textScaler $scale)',
          (WidgetTester tester) async {
            final Booking booking = _shortBooking(id: 'narrow-lane').copyWith(
              serviceName:
                  'Комплексний догляд за волоссям з ботоксом та укладкою',
            );

            await tester.pumpApp(
              Center(
                child: SizedBox(
                  width: lane,
                  child: MasterBookingCard(booking: booking, onTap: () {}),
                ),
              ),
              textScaleFactor: scale,
            );
            await tester.pump();

            expect(tester.takeException(), isNull);
            expect(
              find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
              findsOneWidget,
            );

            final ({double clientName, double service})? floor =
                _compactShareFloors(lane, scale);
            expect(
              floor,
              isNotNull,
              reason:
                  'no measured share floors recorded for lane $lane at '
                  'textScaler $scale — add them to _compactShareFloors rather '
                  'than letting the sweep run unpinned',
            );

            final double nameWidth = tester
                .renderObject<RenderBox>(find.text(booking.clientName!))
                .size
                .width;
            expect(
              nameWidth,
              greaterThan(floor!.clientName),
              reason:
                  'the CLIENT NAME rendered at ${nameWidth}dp in a '
                  '${lane.toInt()}dp lane at textScaler $scale — row 1\'s '
                  'widened start–end label (or the status dot) has eaten the '
                  'row. Shrink the range, not the name.',
            );

            final double serviceWidth = tester
                .renderObject<RenderBox>(find.text(booking.serviceName))
                .size
                .width;
            expect(
              serviceWidth,
              greaterThan(floor.service),
              reason:
                  'the SERVICE NAME rendered at ${serviceWidth}dp in a '
                  '${lane.toInt()}dp lane at textScaler $scale — row 2\'s '
                  'price pill has eaten the row.',
            );
          },
        );
      }
    }

    // The FULL layout's own narrow-lane budget. UNCHANGED by the miniature
    // pass (that pass touched only `_buildCompactBody`, `_PriceTag`'s new
    // default-3 padding knob and the status-dot sibling), and kept because it
    // is the row the range change actually touched: the change made it
    // NARROWER, not wider — the retired «20 лип, 09:00» caption measures
    // 70.88dp in `VelvetText.masterCardDateFull` against the range's 63.76dp
    // (92.13 vs 82.86 at textScaler 1.3). This pins that gain so a future
    // edit cannot quietly hand it back.
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets(
        'the FULL layout keeps a usable service column in the narrowest '
        '226dp lane (textScaler $scale)',
        (WidgetTester tester) async {
          final Booking booking =
              _shortBooking(
                id: 'narrow-lane-full',
                durationMinutes: 60,
              ).copyWith(
                serviceName:
                    'Комплексний догляд за волоссям з ботоксом та укладкою',
              );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: booking,
                  onTap: () {},
                  minHeight: 120,
                ),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(
              const Key('master-booking-card-divider-narrow-lane-full'),
            ),
            findsOneWidget,
            reason: 'precondition: this must be the FULL layout',
          );
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          _expectNoDateOnCard(booking);

          // Measured 80.24dp at 1.0 and 61.14dp at 1.3; floors carry ~10dp of
          // slack.
          final double serviceWidth = tester
              .renderObject<RenderBox>(find.text(booking.serviceName))
              .size
              .width;
          expect(serviceWidth, greaterThan(scale == 1.0 ? 70 : 50));
        },
      );
    }
  });

  // ── THE ROW-1 SWAP'S ONE PLAUSIBLE REGRESSION SURFACE (2026-07-24) ────────
  //
  // Moving the `Expanded` client name from the row's TRAIL to its LEAD does
  // not change how a `Row` divides space — flex gets what the non-flex
  // siblings leave, order-independently — so the swap cannot alter the WIDTH
  // budget, and the sweep above already pins that. What the swap DOES move is
  // which element sits against the row's saturation boundary: the ellipsis is
  // now on the LEADING child, and the fixed-width range it must never push
  // off the row is now DOWNSTREAM of it rather than upstream.
  //
  // The pre-swap suite never rendered a client name long enough to reach that
  // boundary — every fixture used «Марія Іванюк» (~62dp against ~98dp of
  // allotment), so the `Expanded` never actually clipped and `maxLines: 1` +
  // ellipsis were carried untested. These cases saturate it deliberately.
  //
  // WHY THE GAP ASSERTION IN THE ORDER TEST IS NOT ENOUGH (mobile-security
  // raised this as a precision note, explicitly NOT a security finding):
  // `timeRect.left - nameRect.right` measures from the `Expanded` BOX's edge,
  // not from the last glyph, so it pins the LAYOUT gap and would stay green
  // for a name that ellipsised short of its box or drifted right inside it.
  // The 'a SHORT name leaves slack' case below closes exactly that hole by
  // measuring the PAINTED line against the box it was allotted.
  group('a long client name saturates row 1 without breaking it', () {
    // Long enough to blow past ~98dp of allotment at every scale, and a real
    // Ukrainian double-barrelled name rather than a keyboard mash — a
    // fixture literal, never a finder (forbid_cyrillic_finder.sh).
    const String longName = 'Олександра-Валентина Кириленко-Вишневецька';

    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets(
        'in the narrowest 226dp lane at textScaler $scale it ellipsises on '
        'ONE line, the range stays whole, and the row does not overflow',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking(id: 'long-name').copyWith(
            clientFirstName: 'Олександра-Валентина',
            clientLastName: 'Кириленко-Вишневецька',
          );
          expect(
            booking.clientName,
            longName,
            reason: 'precondition: the fixture must build the saturating name',
          );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(booking: booking, onTap: () {}),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();

          // `pumpApp` installs the overflow guard, so a RenderFlex overflow
          // fails this on its own; this pins its ABSENCE explicitly.
          expect(tester.takeException(), isNull);

          // The range renders WHOLE beside a saturating name.
          //
          // HONEST SCOPE (mutation-checked, do not oversell this line): it
          // does NOT by itself catch the `Expanded` moving onto the range.
          // Verified 2026-07-24 by mutating the row to
          // `Flexible(name) … Expanded(range)` — both flex children then take
          // flex 1 and split the free space, so the range still got ~100dp
          // against its 66dp (1.0) / 87dp (1.3) intrinsic and this assertion
          // stayed GREEN. What actually catches that mutation is the
          // `Expanded`-placement assertion below and the short-name slack
          // case at the end of this group (which went RED on it). This line
          // is kept as a cheap direct guard on the user-visible property.
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
            reason: 'the range must render WHOLE beside a saturating name',
          );

          // THE INVARIANT ITSELF, asserted structurally rather than inferred
          // from widths: the flex is on the NAME and the range is non-flex.
          // That is the whole reason the fixed-width range can never be
          // squeezed, and it is the single property the 2026-07-24 swap had
          // to preserve while moving the two children past each other.
          expect(
            find.ancestor(
              of: find.text(longName),
              matching: find.byType(Expanded),
            ),
            findsOneWidget,
            reason:
                'the Expanded must stay on the CLIENT NAME — it is the '
                'variable-length field and the one carrying the ellipsis',
          );
          expect(
            find.ancestor(
              of: find.text(
                formatSlotTimeRange(booking.startAt, booking.endAt),
              ),
              matching: find.byType(Expanded),
            ),
            findsNothing,
            reason:
                'the range must stay NON-FLEX — a fixed-width label that '
                'must never truncate, whichever side of the name it sits on',
          );

          final RenderParagraph name = tester.renderObject<RenderParagraph>(
            find.text(longName),
          );
          expect(
            name.didExceedMaxLines,
            isTrue,
            reason:
                'the name must actually ELLIPSISE at this width — if this is '
                'false the fixture stopped saturating the row and every '
                'assertion here went vacuous',
          );
          expect(
            _paintedLineCount(name),
            1,
            reason:
                'the name must stay on ONE line: a wrap would grow row 1 and '
                'blow the compact card\'s 39dp content budget',
          );

          // Order and gaps SURVIVE saturation — the same three properties the
          // order test pins on a short name, re-pinned at the boundary where
          // the flex child is actually clipping.
          final Rect nameRect = tester.getRect(find.text(longName));
          final Rect timeRect = tester.getRect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
          );
          final Rect dotRect = tester.getRect(find.byType(TimelineStatusDot));
          expect(nameRect.left, lessThan(timeRect.left));
          expect(
            timeRect.left - nameRect.right,
            closeTo(VelvetSpacing.xs + 2, 0.01),
            reason:
                'the 6dp gap must hold even when the name is clipping into '
                'it — measured ${timeRect.left - nameRect.right}dp',
          );
          expect(
            dotRect.left - timeRect.right,
            closeTo(VelvetSpacing.xs, 0.01),
          );

          // GLYPHS vs BOX at saturation. The measured result is worth
          // recording because it is NOT the intuitive one: even a name that
          // is genuinely clipping paints noticeably SHORT of its box (118.93
          // in a 127.04dp box at scale 1.0, an 8.1dp shortfall; 89.55 in
          // 109.65 at 1.3, a 20.1dp shortfall — re-measured for the
          // 2026-08-15 font-size pass, was 105.63/118.35 and 85.96/98.42),
          // because the ellipsis breaks at a grapheme boundary and the
          // remainder of the last cluster is simply not drawn.
          //
          // So the order test's `timeRect.left - nameRect.right` gap is NEVER
          // the visible gap on this row — not even in the saturated case. It
          // is ~6dp of layout plus ~12.5dp of ellipsis remainder. That is
          // fine (the row cannot collide either way) but it is the reason
          // that assertion must not be read as a whitespace guarantee.
          final double painted = _paintedLineWidth(name);
          expect(
            painted,
            lessThanOrEqualTo(nameRect.width + 0.01),
            reason:
                'the painted line (${painted}dp) must never exceed its '
                '${nameRect.width}dp box — that would bleed into the 6dp gap '
                'and collide with the range',
          );
          expect(
            nameRect.width - painted,
            lessThan(21),
            reason:
                'a clipping line should still reach within a cluster of its '
                'box edge; painted ${painted}dp in a ${nameRect.width}dp box '
                '(shortfall ${nameRect.width - painted}dp). A large shortfall '
                'means the name stopped filling the row it was given. Bound '
                'raised 20 -> 21 for the 2026-08-15 font-size pass (measured '
                '20.1dp at scale 1.3, was comfortably under 20 pre-pass) — '
                'still ~1dp of headroom, not a rubber-stamped pass.',
          );
        },
      );
    }

    testWidgets(
      'a SHORT name leaves real slack inside its box — proving the 6dp gap '
      'assertion measures the LAYOUT gap, not visible whitespace',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(id: 'short-name-slack');

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          ),
        );
        await tester.pump();

        final RenderParagraph name = tester.renderObject<RenderParagraph>(
          find.text(booking.clientName!),
        );
        expect(
          name.didExceedMaxLines,
          isFalse,
          reason: 'precondition: the default fixture must NOT be saturating',
        );

        final double boxWidth = tester
            .getRect(find.text(booking.clientName!))
            .width;
        final double painted = _paintedLineWidth(name);

        // The point of the case: the box is MUCH wider than the glyphs, so
        // the 6dp box-edge gap the order test pins is not what a user sees
        // between the name and the range. Pinning the slack is what makes a
        // silent `textAlign: TextAlign.end` — which would slide the glyphs
        // right and collapse the VISIBLE gap to 6dp while every box-edge
        // assertion stayed green — a failure rather than a no-op.
        expect(
          painted,
          lessThan(boxWidth - 20),
          reason:
              'the short name painted ${painted}dp inside a ${boxWidth}dp '
              'box; if these converged the name is no longer start-aligned '
              'in its Expanded, or the row stopped giving it the slack',
        );

        // Start-aligned: the glyphs begin at the box's own left edge. Boxes
        // are paragraph-local, so 0 IS the box's left edge here.
        final List<TextBox> boxes = name.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: booking.clientName!.length,
          ),
        );
        expect(boxes, isNotEmpty);
        expect(
          boxes.first.left,
          closeTo(0, 0.01),
          reason:
              'the name must be START-aligned in its Expanded — a trailing '
              'alignment would keep every box-edge assertion green while '
              'moving the glyphs against the range',
        );
      },
    );
  });

  group('border visibility (2026-07-20 design-parity pass)', () {
    testWidgets(
      'the card border uses the bumped 0.38-alpha / 1.5dp stroke, not the '
      'old 0.18-alpha / 1dp one — catches a silent revert',
      (WidgetTester tester) async {
        const Key cardKey = Key('master-booking-card-border-card');
        final Booking booking = _shortBooking(id: 'border-card');

        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        final AnimatedContainer cardContainer = tester
            .widget<AnimatedContainer>(
              find
                  .descendant(
                    of: find.byKey(cardKey),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            );
        final BoxDecoration decoration =
            cardContainer.decoration! as BoxDecoration;
        final Border border = decoration.border! as Border;

        expect(
          border.top.width,
          1.5,
          reason: 'border width must be the bumped 1.5dp, not the old 1dp',
        );
        expect(
          border.top.color,
          BrandColors.accent.withValues(alpha: 0.38),
          reason:
              'border alpha must be the bumped 0.38, not the old 0.18 — a '
              'silent revert here would make the "much more visible" '
              'border ask regress unnoticed.',
        );
      },
    );

    testWidgets(
      'the compact hairline is the same BrandColors.faint rule the full '
      'layout draws, run full-bleed inside the padding',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: _shortBooking(id: 'hairline'),
                onTap: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        final Finder divider = find.byKey(
          const Key('master-booking-card-compact-divider-hairline'),
        );
        expect(tester.widget<Container>(divider).color, BrandColors.faint);
        expect(tester.getSize(divider).height, 1);

        // Full-bleed inside the padding, not inset — an inset rule at 226dp
        // reads as decoration, edge-to-edge reads as structure.
        final Rect card = tester.getRect(
          find.byKey(const Key('master-booking-card-hairline')),
        );
        final Rect rule = tester.getRect(divider);
        const double inset = VelvetSpacing.sm + 2 + 1.5; // padding + border
        expect(rule.left - card.left, closeTo(inset, 0.01));
        expect(card.right - rule.right, closeTo(inset, 0.01));
      },
    );
  });

  // A booking made against a service the master had left as a genuine RANGE
  // carries BOTH `price` (floor) and `priceMax` (ceiling), frozen server-side
  // at booking time. The pill must render the band — the shipped bug was that
  // it showed the floor alone — and, because it is a NON-flex child beside an
  // `Expanded` service name, the wider two-number string must not be able to
  // trip a RenderFlex overflow on a narrow timeline lane.
  group('frozen RANGE price band', () {
    testWidgets('the compact layout renders «300–500 ₴», not the floor alone', (
      WidgetTester tester,
    ) async {
      final Booking booking = _shortBooking().copyWith(
        price: 300,
        priceMax: 500,
      );

      await tester.pumpApp(
        Center(
          child: MasterBookingCard(booking: booking, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('300–500 ₴'), findsOneWidget);
      expect(
        find.text('300 ₴'),
        findsNothing,
        reason: 'the floor alone is exactly the bug this fixes',
      );
    });

    testWidgets('the full layout (>=115dp) renders the band too', (
      WidgetTester tester,
    ) async {
      final Booking booking = _shortBooking(
        durationMinutes: 60,
      ).copyWith(price: 300, priceMax: 500);

      await tester.pumpApp(
        Center(
          child: MasterBookingCard(
            booking: booking,
            onTap: () {},
            minHeight: 120,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('300–500 ₴'), findsOneWidget);
    });

    testWidgets(
      'a null priceMax still renders the SINGLE price — null is not a missing '
      'value',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking();
        expect(booking.priceMax, isNull);

        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(find.text('450 ₴'), findsOneWidget);
      },
    );

    // The price pill is a NON-flex child beside an `Expanded` service name, so
    // a wider two-number band eats into the name's share rather than the other
    // way round — but if the pill's own intrinsic width ever exceeded what the
    // row had left, the `Expanded` would be squeezed to zero and the Row would
    // overflow. `_PriceTag` caps its text at 96dp and scales down, which keeps
    // the worst band this card can be asked to draw inside the lane's budget.
    //
    // THE TWO WIDTHS ARE BOTH REAL — 272 is `BookingsTimelineGrid._kCardW`,
    // and since "ADDENDUM 3" (that file) it is a CEILING rather than a fixed
    // width: the grid clamps it to `constraints.maxWidth`, so a 360dp device
    // renders 266 (`360 − 94`).
    //
    // 266 IS NOT THE FLOOR. An earlier version of this very comment claimed
    // "266 is therefore the narrowest lane production ever builds this card
    // at". It is not — `320 − 94 = 226` is, because 320dp is a supported
    // width (`test/golden/helpers/golden_pump.dart`'s `kGoldenWidths` is
    // {320, 360, 414}, and `android/app/build.gradle.kts`'s `minSdk = 26`
    // keeps 320dp hardware in the fleet). That restatement is what hid the
    // 226dp overflow this file now sweeps for: the arithmetic in
    // `bookings_timeline_grid.dart` was always right, only the "narrowest
    // device" gloss on top of it was wrong, and it was copied into three
    // places before anyone re-derived it. This pair of lanes is therefore the
    // WIDE end of the coverage; the floor is covered by "THE 226dp NARROW-LANE
    // SWEEP" below and by the "start–end time range" group's own per-lane,
    // per-scale sweep. Do not reintroduce a "narrowest lane" claim here.
    //
    // WHY "a hypothetical 200dp lane" WAS RETIRED FROM THIS SLOT (and why QA
    // signed that off, 2026-07-21 re-audit — do not re-litigate)
    // -------------------------------------------------------------------
    // This slot previously held a 200dp entry. It was RETIRED, not weakened,
    // when the card's time label became a start–end range: the range roughly
    // doubles the leading label, and (in the then-current single-row layout)
    // the row's non-flex children no longer fit 200dp's ~177dp of inner
    // width, so the pathological-band case below overflowed by 12dp there.
    //
    // 200dp is UNREACHABLE: the lane is `min(272, deviceWidth − 94)`, so
    // reaching 200 would need a 294dp device, well under the 320dp floor
    // cited above.
    for (final ({String label, double width}) lane
        in <({String label, double width})>[
          (label: 'the production 272dp lane', width: 272),
          (label: 'the narrowest clamped 266dp lane', width: 266),
        ]) {
      testWidgets(
        'the longest band + a long service name stay inside ${lane.label}',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking().copyWith(
            serviceName:
                'Комплексний догляд за волоссям з ботоксом та укладкою',
            price: 12500,
            priceMax: 25000,
          );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: lane.width,
                child: MasterBookingCard(booking: booking, onTap: () {}),
              ),
            ),
          );
          await tester.pump();

          // `pumpApp` installs the shared overflow guard, so a RenderFlex
          // overflow here fails the test on its own; this pins the absence of
          // any other thrown layout error too.
          expect(tester.takeException(), isNull);
          expect(find.text('12500–25000 ₴'), findsOneWidget);

          // This band FITS — it does not exercise the cap. 83.8dp of text
          // against a 96dp cap means `FittedBox` resolves to scale 1.0 and
          // the `ConstrainedBox` never binds, so on its own this case proves
          // only "the realistic worst band needs no scaling". The cap
          // MECHANISM is exercised by the group below; pinned here so the two
          // cases can never silently collapse into one.
          expect(
            _priceTextWidth(tester),
            lessThan(_kPriceCapWidth),
            reason:
                'the realistic worst band must stay UNDER the cap — if this '
                'ever fails the cap has been lowered into real data, and the '
                'over-cap group below is no longer testing anything extra',
          );
          expect(_fittedPriceWidth(tester), _priceTextWidth(tester));
        },
      );
    }

    // FINDING-3 REGRESSION — the group above measures 83.8dp against a 96dp
    // cap, so it never actually engages `_PriceTag`'s `ConstrainedBox` +
    // `FittedBox(scaleDown)`. These cases push a deliberately pathological
    // band past the cap and assert the scale-down REALLY fires.
    for (final ({String label, double width}) lane
        in <({String label, double width})>[
          (label: 'the production 272dp lane', width: 272),
          (label: 'the narrowest clamped 266dp lane', width: 266),
        ]) {
      testWidgets(
        'an OVER-cap band actually engages the width cap in ${lane.label}',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking().copyWith(
            serviceName:
                'Комплексний догляд за волоссям з ботоксом та укладкою',
            price: 1234567,
            priceMax: 8901234,
          );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: lane.width,
                child: MasterBookingCard(booking: booking, onTap: () {}),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);

          // The text's own render box keeps its NATURAL size — `FittedBox`
          // scales via a transform, it does not re-lay-out its child — so
          // comparing the two boxes is a direct read of whether the scale
          // engaged. Observed: natural 110.97dp vs fitted 96.0dp (scale
          // ~0.865).
          final double natural = _priceTextWidth(tester);
          final double fitted = _fittedPriceWidth(tester);
          expect(
            natural,
            greaterThan(_kPriceCapWidth),
            reason:
                'the fixture must out-measure the cap or this proves nothing',
          );
          expect(
            fitted,
            _kPriceCapWidth,
            reason: 'the ConstrainedBox must clamp the band at exactly the cap',
          );
          expect(
            fitted,
            lessThan(natural),
            reason: 'scaleDown must have fired',
          );

          // The pill's own box clamps at cap + its horizontal padding, and the
          // band is still whole — scaled, never ellipsised or clipped.
          expect(
            _priceTagWidth(tester),
            _kPriceCapWidth + VelvetSpacing.sm * 2,
          );
          expect(find.text('1234567–8901234 ₴'), findsOneWidget);
        },
      );
    }

    // THE 226dp NARROW-LANE SWEEP (2026-07-21 audit fix) — the corner both
    // layouts actually overflowed in, kept and re-measured through the
    // miniature pass.
    //
    // Before the fix, at the true floor (226dp — a 320dp device, see the
    // "start–end time range" group's own note on why 226 and not 266) BOTH
    // layouts overflowed once a frozen band was present:
    //
    //   * the OLD compact row 1 (range + service + price on ONE row) — clean
    //     at 1.0/1.15, 5.6px over at 1.3.
    //   * full row 3 — 6.6px over at 1.0 (with a cap-binding band), 16px at
    //     1.15, 26px at 1.3. Two non-flex children (`_PriceTag`,
    //     `TimelineStatusBadge`) either side of a `Spacer` simply cannot fit
    //     191dp of inner width.
    //
    // The full layout is still held by `Expanded` + `Align`. The compact
    // layout no longer has the problem at all: splitting the row moved the
    // price off the time label, so row 2's only non-flex child is a
    // self-capping 112dp pill against 203dp of row. That shows up here as a
    // large, measured jump in what the service name keeps — from 35.35dp to
    // 99.23dp at textScaler 1.0 — which is exactly the property
    // `_narrowServiceFloors` now pins.
    for (final double scale in <double>[1.0, 1.15, 1.3]) {
      for (final ({String label, double price, double priceMax}) band
          in <({String label, double price, double priceMax})>[
            (label: 'the realistic worst band', price: 12500, priceMax: 25000),
            (
              label: 'a pathological 7-digit band',
              price: 1234567,
              priceMax: 8901234,
            ),
          ]) {
        for (final ({String label, double? minHeight, int duration}) layout
            in <({String label, double? minHeight, int duration})>[
              (label: 'compact', minHeight: null, duration: 20),
              (label: 'full', minHeight: 120, duration: 60),
            ]) {
          testWidgets(
            '${band.label} fits the ${layout.label} layout in the narrowest '
            '226dp lane (textScaler $scale)',
            (WidgetTester tester) async {
              final Booking booking =
                  _shortBooking(
                    id: 'narrow-band-${layout.label}',
                    durationMinutes: layout.duration,
                  ).copyWith(
                    serviceName:
                        'Комплексний догляд за волоссям з ботоксом та укладкою',
                    price: band.price,
                    priceMax: band.priceMax,
                  );

              await tester.pumpApp(
                Center(
                  child: SizedBox(
                    width: 226,
                    child: MasterBookingCard(
                      booking: booking,
                      onTap: () {},
                      minHeight: layout.minHeight,
                    ),
                  ),
                ),
                textScaleFactor: scale,
              );
              await tester.pump();

              expect(tester.takeException(), isNull);

              // The band is still WHOLE — `scaleDown` shrinks, it never
              // ellipsises, so absorbing the pressure must not have cost a
              // digit.
              expect(find.text(booking.priceLabel), findsOneWidget);
              // …and the range is still a range, still date-free.
              expect(
                find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
                findsOneWidget,
              );
              _expectNoDateOnCard(booking);

              // THE PILL NEVER EXCEEDS ITS OWN CEILING (96dp of capped text
              // plus 2 × `VelvetSpacing.sm`).
              //
              // This assertion CHANGED SHAPE in the miniature pass and the
              // change is deliberate. It used to demand `pill < ceiling` —
              // "the row is actively holding the pill under its ceiling" —
              // as a non-vacuity guard on `_kCompactPriceReserve`. That
              // referent is gone: the re-derived 68dp reserve resolves to a
              // 135dp cap at 226dp, ABOVE the 112dp ceiling, so the cap no
              // longer binds anywhere production can reach and the pill
              // legitimately measures exactly 112. Keeping the strict `<`
              // would have failed on correct code. The non-vacuity it used to
              // provide is carried instead by the service-name floors below,
              // which rose from 30/20/10dp to 80dp precisely BECAUSE the pill
              // stopped being squeezed — a much stronger statement about the
              // same row.
              final double pill = _priceTagWidth(tester);
              const double ceiling = _kPriceCapWidth + VelvetSpacing.sm * 2;
              expect(
                pill,
                lessThanOrEqualTo(ceiling),
                reason:
                    'the pill measured ${pill}dp — above its own ${ceiling}dp '
                    'ceiling, so `_PriceTag`\'s text cap has stopped binding '
                    'and the row is back to an unbounded non-flex contract',
              );

              // The service name is what must NOT have paid for the fit
              // beyond the ellipsis it was always allowed to take. Floors
              // are PER SCALE and PER LAYOUT — see [_narrowServiceFloors].
              final ({double compact, double full})? floors =
                  _narrowServiceFloors(scale);
              expect(
                floors,
                isNotNull,
                reason:
                    'no measured service-name floor recorded for textScaler '
                    '$scale — add one to _narrowServiceFloors rather than '
                    'letting the sweep run unpinned',
              );
              final double serviceWidth = tester
                  .renderObject<RenderBox>(find.text(booking.serviceName))
                  .size
                  .width;
              expect(
                serviceWidth,
                greaterThan(
                  layout.label == 'full' ? floors!.full : floors!.compact,
                ),
                reason:
                    'the service name rendered at ${serviceWidth}dp in the '
                    '${layout.label} layout at textScaler $scale — the '
                    'overflow must be absorbed by the price pill scaling '
                    'down, not by squeezing the name out of the card',
              );
            },
          );
        }
      }
    }

    // FINDING-5 REGRESSION — `BoxFit.scaleDown` scales UNIFORMLY, so before
    // `_PriceTag` grew its zero-width height anchor an over-cap band shrank
    // the pill's HEIGHT too (measured: text 15.0dp -> 13.0dp, pill 21 -> 19),
    // quietly dragging the compact card under
    // `MasterBookingCard.estimatedNaturalHeight`. The anchor holds the pill at
    // its natural line height whatever the horizontal scale.
    //
    // SWEPT ACROSS textScaler, and that sweep is the point (perf P2). At the
    // default 1.0 a `SizedBox(height: 15)` would satisfy this test exactly as
    // well as the `Text` anchor does — 15.0 IS the line height there — so a
    // 1.0-only case cannot tell a scale-aware anchor from a frozen constant
    // and silently blesses the swap. Above 1.0 the two diverge: the `Text`
    // re-derives its height from the inherited scaler, the box cannot see it.
    // 1.3 is the app's own MediaQuery ceiling (`main.dart`), i.e. a scale real
    // users reach, not a synthetic one.
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('an OVER-cap band does not shrink the price pill vertically '
          '(textScaler $scale)', (WidgetTester tester) async {
        Future<({double pill, double card})> measure(
          double price,
          double priceMax,
        ) async {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 272,
                child: MasterBookingCard(
                  booking: _shortBooking().copyWith(
                    price: price,
                    priceMax: priceMax,
                  ),
                  onTap: () {},
                ),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();
          return (
            pill: tester
                .renderObject<RenderBox>(find.byType(NeumorphicInset).first)
                .size
                .height,
            card: tester
                .renderObject<RenderBox>(find.byType(MasterBookingCard))
                .size
                .height,
          );
        }

        final ({double pill, double card}) inCap = await measure(12500, 25000);
        final ({double pill, double card}) overCap = await measure(
          1234567,
          8901234,
        );

        expect(
          overCap.pill,
          inCap.pill,
          reason:
              'the height anchor must keep the pill at its natural line '
              'height even when the width cap scales the band down',
        );
        expect(overCap.card, inCap.card);
        expect(
          overCap.card,
          greaterThanOrEqualTo(MasterBookingCard.estimatedNaturalHeight - 2),
          reason:
              'a scaled band must not drag the card under its documented '
              'natural height',
        );
      });
    }
  });

  // ── mobile-qa audit additions (2026-07-21) ────────────────────────────────
  //
  // Three properties the pass DEPENDS on that the suite above states in prose
  // but does not fail on. Figures below are historical (as measured in
  // 2026-07-21, box 56 / budget 41); the 2026-08-15 font-size pass moved
  // them to box 54 / budget 39 — see the group below, which asserts the
  // CURRENT numbers.
  //
  //   1. The 41dp budget is pinned only as a TOTAL (`height == 56`). The
  //      derivation it is justified by — `56 − 3 (border) − 12 (padding) = 41`,
  //      spent as `15 + 4 + 1 + 4 + 17` — is nowhere asserted, so a
  //      compensating edit (padding +1, border −0.5) or a re-balanced stack
  //      (gap 6 / pill 15) lands on 56 again and ships a card whose documented
  //      arithmetic is fiction. The whole point of "sized TO the box rather
  //      than measured after the fact" is that each TERM is a commitment.
  //   2. `_PriceTag.verticalPadding`'s default is pinned (the pill measures 21
  //      in the full layout), but the FULL BODY's own height is not — it is
  //      only bounded below (`> 114`). A compact-only change that leaked into
  //      the shared layout and made the >=1h card TALLER would pass every
  //      existing case. "The >=1h card renders byte-identically" was proven by
  //      one-off measurement; this pins it.
  //   3. `_timelineStatusVisual` is asserted from the DOT's side only. Its
  //      stated guarantee is that the dot and the badge cannot fork — a
  //      re-forked BADGE (hard-coded accents in `TimelineStatusBadge`) leaves
  //      every existing case green, including the six-status dot sweep, which
  //      compares the dot against the shared factory and never looks at the
  //      badge at all.
  group('the compact budget, decomposed — every term, not just the total', () {
    testWidgets(
      'the 15dp of chrome and the 39dp of content are separately pinned, and '
      'the content stack spends 14 + 4 + 1 + 4 + 16',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(id: 'budget-terms');

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          ),
        );
        await tester.pump();

        final Rect card = tester.getRect(
          find.byKey(const Key('master-booking-card-budget-terms')),
        );
        // Row 1's tallest child IS the row (the range label is 12dp and the
        // dot 8dp against the name's 14dp, under `CrossAxisAlignment.center`
        // — was 13dp/15dp before the 2026-08-15 font-size pass), and row 2's
        // tallest child is the pill — so these two rects delimit the content
        // region exactly.
        final Rect name = tester.getRect(find.text(booking.clientName!));
        final Rect rule = tester.getRect(
          find.byKey(
            const Key('master-booking-card-compact-divider-budget-terms'),
          ),
        );
        final Rect pill = tester.getRect(
          find.ancestor(
            of: find.text('450 ₴'),
            matching: find.byType(NeumorphicInset),
          ),
        );

        // ── THE CHROME: border 1.5 × 2 + `_compactPadding`'s vertical 6 × 2.
        //      Split top/bottom so a one-sided padding edit cannot cancel out
        //      against the other side. ────────────────────────────────────────
        expect(
          name.top - card.top,
          closeTo(7.5, 0.01),
          reason:
              'the top chrome measured ${name.top - card.top}dp against the '
              'documented 1.5 (border) + 6 (_compactPadding vertical) = 7.5. '
              'Either _kBorderWidth or _compactPadding moved and the 39dp '
              'budget derivation on estimatedNaturalHeight is now wrong.',
        );
        expect(
          card.bottom - pill.bottom,
          closeTo(7.5, 0.01),
          reason: 'the bottom chrome must mirror the top exactly',
        );

        // ── THE CONTENT: 39dp (was 41dp before the 2026-08-15 font-size
        //      pass), and the five terms that spend it. ─────────────────────
        expect(
          pill.bottom - name.top,
          closeTo(39, 0.01),
          reason:
              'the content region measured ${pill.bottom - name.top}dp against '
              'the documented 39dp budget',
        );
        for (final ({String label, double actual, double expected}) term
            in <({String label, double actual, double expected})>[
              (
                label: 'row 1 (the client name)',
                actual: name.height,
                expected: 14,
              ),
              (
                label: 'the gap above the hairline (VelvetSpacing.xs)',
                actual: rule.top - name.bottom,
                expected: 4,
              ),
              (label: 'the hairline', actual: rule.height, expected: 1),
              (
                label: 'the gap below the hairline (VelvetSpacing.xs)',
                actual: pill.top - rule.bottom,
                expected: 4,
              ),
              (
                label: 'row 2 (the price pill, 14dp line + 1dp padding × 2)',
                actual: pill.height,
                expected: 16,
              ),
            ]) {
          expect(
            term.actual,
            closeTo(term.expected, 0.01),
            reason:
                '${term.label} measured ${term.actual}dp against its budgeted '
                '${term.expected}dp. The card still fits 54dp only because '
                'another term absorbed the difference — the derivation on '
                'MasterBookingCard.estimatedNaturalHeight is no longer true '
                'even though the total test is green.',
          );
        }

        // …and the terms really do sum to the whole box, so no sixth term can
        // be added without one of the five above shrinking to pay for it.
        expect(
          name.height +
              (rule.top - name.bottom) +
              rule.height +
              (pill.top - rule.bottom) +
              pill.height +
              15, // 3 border + 12 padding
          closeTo(MasterBookingCard.estimatedNaturalHeight, 0.01),
        );
      },
    );

    // The other half of `_PriceTag.verticalPadding`'s default-3 contract: the
    // existing pill test proves the PILL is 20dp in the full layout (was
    // 21dp before the 2026-08-15 font-size pass — see
    // `VelvetText.masterCardPricePill`'s doc); this proves the full BODY's
    // own height did not move by MORE than the font-size pass's own,
    // separately-measured delta. Exact, not a floor — "the >=1h card renders
    // byte-identically [aside from the font-size pass]" is the claim, and a
    // floor cannot express it.
    for (final ({double scale, double height}) fullNatural
        in <({double scale, double height})>[
          (scale: 1.0, height: 115),
          (scale: 1.15, height: 120),
          (scale: 1.3, height: 126),
        ]) {
      testWidgets(
        'the FULL body still measures exactly ${fullNatural.height}dp at '
        'textScaler ${fullNatural.scale} — the compact pass did not leak',
        (WidgetTester tester) async {
          final Booking booking =
              _shortBooking(id: 'full-pinned', durationMinutes: 60).copyWith(
                serviceName:
                    'Комплексний догляд за волоссям з ботоксом та укладкою',
                price: 12500,
                priceMax: 25000,
              );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: booking,
                  onTap: () {},
                  // Pumped exactly at the switch (== fullLayoutNaturalHeight,
                  // 115 as of the 2026-08-15 font-size pass, was 118): the
                  // LOWEST minHeight that selects the full body. At
                  // textScaler 1.0 box == floor == the 115dp natural; at 1.15
                  // and 1.3 the content grows to 120 / 126 STRICTLY past this
                  // floor, so those two are genuine content measurements and
                  // catch any leak from the compact pass. (Since ADDENDUM 7
                  // set the switch equal to the 1.0 natural, a below-natural
                  // floor can no longer select the full layout, so the 1.0
                  // point is pinned at the switch rather than as free content.)
                  minHeight: MasterBookingCard.fullLayoutMinHeight,
                ),
              ),
            ),
            textScaleFactor: fullNatural.scale,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('master-booking-card-divider-full-pinned')),
            findsOneWidget,
            reason: 'precondition: this must be the FULL layout',
          );

          final double height = tester
              .getSize(find.byKey(const Key('master-booking-card-full-pinned')))
              .height;
          expect(
            height,
            closeTo(fullNatural.height, 0.01),
            reason:
                'the full body measured ${height}dp against the '
                '${fullNatural.height}dp recorded in _kFullLayoutMinHeight\'s '
                'measurement table. The compact pass is supposed to leave this '
                'layout byte-identical — the usual leak is _PriceTag\'s '
                'verticalPadding default drifting off 3, or a shared spacing '
                'token being retuned for the compact card\'s benefit.',
          );
        },
      );
    }
  });

  // The stated guarantee of `_timelineStatusVisual`: the dot and the badge
  // resolve colour AND label through ONE call, so they cannot disagree about
  // what a status means. The six-status sweep above pins the DOT against the
  // shared factory; nothing pins the BADGE, so a re-forked badge (hard-coded
  // accents, or a second `BookingStatusVisual.of` call site that a later edit
  // touches alone) ships a card whose colour and whose tooltip disagree with
  // the >=1h card's pill — the one failure a colour-only indicator cannot
  // survive. This asserts the two indicators AGAINST EACH OTHER.
  group('the dot and the badge cannot fork', () {
    for (final BookingStatus status in BookingStatus.values) {
      testWidgets(
        'the compact dot and the full badge agree on colour and label for '
        '${status.name}',
        (WidgetTester tester) async {
          Future<({Color accent, String label})> render(
            double minHeight,
            int duration,
          ) async {
            await tester.pumpApp(
              Center(
                child: SizedBox(
                  width: 272,
                  child: MasterBookingCard(
                    booking: _shortBooking(
                      id: 'fork-${status.name}',
                      durationMinutes: duration,
                      status: status,
                    ),
                    onTap: () {},
                    minHeight: minHeight,
                  ),
                ),
              ),
            );
            await tester.pump();

            if (find.byType(TimelineStatusDot).evaluate().isNotEmpty) {
              final BoxDecoration d =
                  tester
                          .widget<DecoratedBox>(
                            find.descendant(
                              of: find.byType(TimelineStatusDot),
                              matching: find.byType(DecoratedBox),
                            ),
                          )
                          .decoration
                      as BoxDecoration;
              // The dot's label lives in the Tooltip/Semantics channel — that
              // IS its label, and comparing it to the pill's rendered text is
              // the whole point of this test.
              return (
                accent: d.color!,
                label: tester
                    .widget<Tooltip>(
                      find.descendant(
                        of: find.byType(TimelineStatusDot),
                        matching: find.byType(Tooltip),
                      ),
                    )
                    .message!,
              );
            }

            // Matched by SHAPE, not by position: `NeumorphicInset` builds
            // containers of its own around the label, so `.first`/`.last` on a
            // bare `byType(Container)` would silently read the recessed well
            // instead of the status glyph — and the well's colour is the same
            // on every status, so the fork this group exists to catch would
            // pass. The badge's glyph is its only CIRCULAR box.
            final BoxDecoration badgeDot =
                tester
                        .widget<Container>(
                          find.descendant(
                            of: find.byType(TimelineStatusBadge),
                            matching: find.byWidgetPredicate(
                              (Widget w) =>
                                  w is Container &&
                                  w.decoration is BoxDecoration &&
                                  (w.decoration! as BoxDecoration).shape ==
                                      BoxShape.circle,
                            ),
                          ),
                        )
                        .decoration!
                    as BoxDecoration;
            return (
              accent: badgeDot.color!,
              label: tester
                  .widget<Text>(
                    find.descendant(
                      of: find.byType(TimelineStatusBadge),
                      matching: find.byType(Text),
                    ),
                  )
                  .data!,
            );
          }

          final ({Color accent, String label}) dot = await render(56, 30);
          final ({Color accent, String label}) badge = await render(120, 60);

          expect(
            dot.accent,
            badge.accent,
            reason:
                'the compact dot and the >=1h pill painted DIFFERENT accents '
                'for ${status.name} — _timelineStatusVisual has been forked, '
                'so the same booking reads as two different statuses '
                'depending on how long it happens to be',
          );
          expect(
            dot.label,
            badge.label,
            reason:
                'the dot\'s tooltip and the pill\'s printed label disagree for '
                '${status.name} — the label is the ONLY channel the dot has, '
                'and it must be the same string the pill shows',
          );
          // …and both really are the shared factory's own values, not merely
          // equal to each other because both were forked the same way.
          expect(
            badge.label,
            BookingStatusVisual.of(
              _shortBooking(status: status),
              AppLocalizations.of(
                tester.element(find.byType(MasterBookingCard)),
              ),
            ).label,
          );
        },
      );
    }
  });

  // The `_kCompactPriceReserve` group that lived here was DELETED 2026-07-22
  // alongside the constant and the per-card `LayoutBuilder` that measured the
  // row for it (mobile-perf MEDIUM — see `master_booking_card.dart`'s row 2
  // comment). It asserted the pill was capped at `row − 68` on a
  // sub-production 190dp lane; there is no cap any more, so there is nothing
  // left for it to pin. The behaviour it actually protected — the price band
  // SCALING rather than clipping or ellipsising when squeezed — is covered by
  // the "the compact budget, decomposed" group above, whose per-lane /
  // per-textScaler sweep reads `_PriceTag`'s OWN `_maxTextWidth` ceiling
  // ([_kPriceCapWidth]) and its `FittedBox` scale, neither of which this
  // removal touches.

  // THE ROW-1 CLIENT GLYPH (2026-07-24) — FULL BODY ONLY
  // ---------------------------------------------------------------------
  // The >=1h card's client-name row gained a leading `person_outlined` glyph
  // in the SAME 16dp/`BrandColors.accent` register row 2's `spa_outlined`
  // already uses (see `master_booking_card.dart`'s row-1 comment for why the
  // 12dp/muted metadata register would have inverted the hierarchy).
  //
  // These are STRUCTURAL assertions, deliberately not goldens: a regenerated
  // golden would accept the glyph landing on the wrong row, in the wrong
  // register, or bleeding into the compact/micro bodies. Each case below
  // names a property that a re-render cannot satisfy by accident.
  group('the FULL body\'s row-1 client glyph', () {
    testWidgets(
      'renders exactly once, in the 16dp accent register, ABOVE the hairline '
      '— i.e. on the client-identity row, not the service row',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: _shortBooking(id: 'glyph', durationMinutes: 60),
                onTap: () {},
                minHeight: MasterBookingCard.fullLayoutMinHeight,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(
          find.byKey(const Key('master-booking-card-divider-glyph')),
          findsOneWidget,
          reason: 'precondition: this must be the FULL layout',
        );

        final Finder glyph = find.byIcon(Icons.person_outlined);
        expect(glyph, findsOneWidget);

        final Icon icon = tester.widget<Icon>(glyph);
        expect(
          icon.size,
          16,
          reason:
              'the client name is this card\'s PRIMARY field, so its glyph '
              'takes the same 16dp register row 2\'s service glyph does — not '
              'the 12dp one the trailing time range uses',
        );
        expect(
          icon.color,
          BrandColors.accent,
          reason:
              'same register means same colour: BrandColors.accent, not the '
              'muted grey reserved for trailing metadata',
        );

        // ROW 1, PROVEN POSITIONALLY. The glyph must sit entirely above the
        // hairline — that is what makes it the CLIENT row's mark rather than
        // a second glyph on the service row.
        final double glyphBottom = tester.getBottomLeft(glyph).dy;
        final double dividerTop = tester
            .getTopLeft(
              find.byKey(const Key('master-booking-card-divider-glyph')),
            )
            .dy;
        expect(
          glyphBottom,
          lessThanOrEqualTo(dividerTop),
          reason:
              'the client glyph rendered at or below the hairline, so it is '
              'no longer on the client-identity row',
        );
      },
    );

    testWidgets(
      'shares a left rail with the service glyph — both open their row at the '
      'same x, so the two text columns align',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: _shortBooking(id: 'rail', durationMinutes: 60),
                onTap: () {},
                minHeight: MasterBookingCard.fullLayoutMinHeight,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          tester.getTopLeft(find.byIcon(Icons.person_outlined)).dx,
          closeTo(tester.getTopLeft(find.byIcon(Icons.spa_outlined)).dx, 0.01),
          reason:
              'the two 16dp glyphs are supposed to form one left rail, which '
              'is what puts the client name and the service name on a single '
              'text column. A drift here means the row-1 glyph picked up a '
              'different leading inset than row 2\'s.',
        );
      },
    );

    // ROW 1 IS A `Row` NOW, SO THE NAME NEEDS `Expanded` (mobile-qa,
    // 2026-07-24). The source comment beside that `Expanded` names the exact
    // failure mode — "an unbounded child would make `maxLines: 1` + ellipsis
    // inert and let a long client name overflow instead of truncating" — but
    // nothing exercised it: the existing "a long client name saturates row 1"
    // group pumps with NO `minHeight`, which selects the COMPACT body, so the
    // saturating fixture never reached the full layout at all. Verified by
    // mutation: deleting this `Expanded` passed the whole booking suite.
    //
    // 1.3 is included because that is where the name is widest AND where the
    // glyph does NOT grow with it, so the `Expanded` is carrying the most.
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets(
        'a saturating client name ellipsises inside row 1 at textScaler '
        '$scale — the glyph never pushes it past the padding edge',
        (WidgetTester tester) async {
          // A real Ukrainian double-barrelled name, as a FIXTURE literal and
          // never a finder (forbid_cyrillic_finder.sh) — the same one the
          // compact-layout saturation group uses, so both densities are
          // stressed by identical content.
          final Booking booking =
              _shortBooking(id: 'long-full', durationMinutes: 60).copyWith(
                clientFirstName: 'Олександра-Валентина',
                clientLastName: 'Кириленко-Вишневецька',
              );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: booking,
                  onTap: () {},
                  minHeight: MasterBookingCard.fullLayoutMinHeight,
                ),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();

          // `pumpApp` installs the overflow guard, so an unbounded row-1 name
          // fails here on the RenderFlex overflow alone.
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('master-booking-card-divider-long-full')),
            findsOneWidget,
            reason: 'precondition: this must be the FULL layout',
          );

          // The name is TRUNCATED, not merely un-crashed: its box must end
          // inside the card's own padding edge. `_fullPadding` is 16 and the
          // border 1.5, so the content edge is 17.5dp in from the card's
          // right. A box reaching past it is the un-`Expanded` failure that
          // the overflow guard can miss whenever the surface happens to be
          // wide enough to absorb it.
          final Rect card = tester.getRect(
            find.byKey(const Key('master-booking-card-long-full')),
          );
          final Rect name = tester.getRect(
            find.descendant(
              of: find.byKey(const Key('master-booking-card-long-full')),
              matching: find.byType(Text).first,
            ),
          );
          expect(
            name.right,
            lessThanOrEqualTo(card.right - 17.5 + 0.01),
            reason:
                'the client name box ends at ${name.right} against the card\'s '
                '${card.right - 17.5} content edge — row 1 stopped bounding '
                'it, so `maxLines: 1` + ellipsis are inert and a long name '
                'runs under the card\'s own padding',
          );
          expect(
            name.height,
            lessThan(MasterBookingCard.microLayoutNaturalHeight),
            reason:
                'the name grew past one line (${name.height}dp) — with the '
                'glyph now sharing the row, a wrapped name is what pushes the '
                'full body past the band its duration owns',
          );
        },
      );
    }

    testWidgets('is DECORATIVE — it adds no second announcement', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 226,
            child: MasterBookingCard(
              booking: _shortBooking(id: 'a11y', durationMinutes: 60),
              onTap: () {},
              minHeight: MasterBookingCard.fullLayoutMinHeight,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<Icon>(find.byIcon(Icons.person_outlined)).semanticLabel,
        isNull,
        reason:
            'the client name is already carried by the card\'s own '
            'Semantics(label:) (masterBookingCardSemantics). Labelling the '
            'glyph too would announce the same person twice to a screen '
            'reader.',
      );
    });

    // The glyph is a FULL-body element. The compact body is documented as a
    // "miniature of the full card", so this pair is the standing guard that
    // the glyph was not quietly propagated down: whether compact should ALSO
    // gain one is a product question, not something a refactor gets to decide
    // silently.
    for (final ({String label, double minHeight, bool compactHairline}) shorter
        in <({String label, double minHeight, bool compactHairline})>[
          (label: 'COMPACT', minHeight: 60, compactHairline: true),
          (label: 'MICRO', minHeight: 30, compactHairline: false),
        ]) {
      testWidgets('does NOT render on the ${shorter.label} body', (
        WidgetTester tester,
      ) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: _shortBooking(id: 'shorter', durationMinutes: 30),
                onTap: () {},
                minHeight: shorter.minHeight,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Precondition: prove which body actually rendered, so a
        // `findsNothing` cannot pass merely because the card failed to build
        // or silently selected a different density.
        //
        // BOTH hairlines are asserted for BOTH densities, and that is the
        // point (mobile-qa, 2026-07-24). The MICRO row previously stated only
        // the "not FULL" half, which COMPACT satisfies just as well — so a
        // regression that sent a 30dp floor to the compact body would have
        // left the MICRO case passing while testing nothing about micro. The
        // layout enum has exactly three branches and full/compact each carry
        // their own distinctly-keyed hairline, so "neither hairline" is the
        // positive identification of micro.
        expect(
          find.byKey(const Key('master-booking-card-divider-shorter')),
          findsNothing,
          reason: 'precondition: this must NOT be the FULL layout',
        );
        expect(
          find.byKey(const Key('master-booking-card-compact-divider-shorter')),
          shorter.compactHairline ? findsOneWidget : findsNothing,
          reason: shorter.compactHairline
              ? 'precondition: this must be the COMPACT layout'
              : 'precondition: the MICRO body is a single row and carries NO '
                    'hairline at all, so neither divider may render — without '
                    'this the MICRO case would pass just as happily against a '
                    'COMPACT card',
        );

        expect(
          find.byIcon(Icons.person_outlined),
          findsNothing,
          reason:
              'the client glyph is a FULL-body element — the ${shorter.label} '
              'body has no vertical budget for a 16dp icon (its naturals are '
              'pinned at 54dp / 27dp and both are already at zero slack)',
        );
      });
    }
  });

  // THE FULL-BODY NATURAL, PINNED IN BOTH DIRECTIONS — and the tight-
  // clearance edge it now sits on (mobile-qa, 2026-07-24; renumbered
  // 2026-08-15)
  // ---------------------------------------------------------------------
  // Two holes the ROW-1 GLYPH pass left behind, both found by mutation:
  //
  //   1. The "the FULL body still measures exactly …dp at textScaler 1.0"
  //      group above pumps at `minHeight: fullLayoutMinHeight`, so the box it
  //      measures is `max(natural, content)`. That pins the natural against
  //      GROWTH only. Deleting the row-1 glyph takes the content back a dp,
  //      the floor pads it straight back to the threshold, and that case
  //      still passes — verified by mutation. So nothing measured the dp the
  //      constant bump is about; only the glyph-presence group did, and a
  //      glyph can be present at the wrong SIZE.
  //   2. THE 2026-08-15 FONT-SIZE PASS WIDENED THIS BLIND SPOT. At the
  //      pre-pass 118dp threshold, a 59-minute booking's floor
  //      (`59/60 × 120 = 118`) landed EXACTLY on the switch — zero
  //      clearance, so ANY growth of the full body was caught by a rendered
  //      card. Post-pass the threshold fell to 115dp — an ODD dp figure no
  //      whole-minute duration lands on exactly (`115 / 120 × 60 = 57.5`
  //      min) — so 59 minutes now clears by 3dp: growth of up to 3dp would
  //      go uncaught by a test still targeting that duration. The tightest
  //      real edge moved to **58 minutes**, whose `58/60 × 120 = 116dp`
  //      floor clears the 115dp natural by exactly **1dp** (see
  //      `master_booking_card_layout_height_test.dart`'s sweep, which
  //      documents the same 58min/1dp and 59min/3dp figures). The boundary
  //      pair elsewhere in this file pumps bare dp literals, which pins the
  //      SWITCH but never asks whether a real duration still reaches it at a
  //      tight margin.
  //
  // Both cases below are floor-INDEPENDENT where it matters: the first
  // measures an interior distance the outer floor cannot pad, the second
  // derives its floor from a duration rather than restating the threshold.
  group('the FULL body\'s 115dp natural, measured from the inside', () {
    testWidgets(
      'row 1 is the GLYPH\'s 16dp, not the client name\'s 15dp line box — the '
      'interior distance from the card\'s top edge to the hairline',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: _shortBooking(id: 'natural', durationMinutes: 60),
                onTap: () {},
                minHeight: MasterBookingCard.fullLayoutMinHeight,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        final Finder divider = find.byKey(
          const Key('master-booking-card-divider-natural'),
        );
        expect(
          divider,
          findsOneWidget,
          reason: 'precondition: this must be the FULL layout',
        );

        // THE BIDIRECTIONAL PIN, asserted FIRST and deliberately: it is the
        // only assertion here that survives the glyph being deleted outright
        // (a `getSize` on an absent icon throws `Bad state: No element`,
        // which is red but says nothing about the constant). Ordering it
        // ahead of the glyph reads means the diagnostic below is what a
        // reviewer actually sees for the mutation this group exists to catch.
        //
        // `border 1.5 + _fullPadding 16 + row 1 +
        // (VelvetSpacing.sm + 2 = 10)` = 43.5dp of interior above the
        // hairline. This distance is INSIDE the card, so the `minHeight`
        // floor cannot pad it: drop the glyph and it reads 42.5, grow the
        // glyph and it reads more. That is the assertion the outer
        // height measurement cannot make.
        final double headroom =
            tester.getRect(divider).top -
            tester
                .getRect(find.byKey(const Key('master-booking-card-natural')))
                .top;
        expect(
          headroom,
          closeTo(43.5, 0.01),
          reason:
              'the card\'s top edge sits ${headroom}dp above the hairline '
              'against the 43.5dp the full body derives (1.5 border + 16 '
              'padding + a 16dp row 1 + 10). 42.5 means the row-1 glyph was '
              'removed and MasterBookingCard.fullLayoutNaturalHeight (115) is '
              'now 1dp larger than the body it claims to measure — which the '
              'outer "measures exactly …dp" case CANNOT see, because it '
              'pumps at that very constant as a floor.',
        );

        // WHICH term wins the row, stated as a strict inequality against the
        // name's own measured line box rather than two literals — so it holds
        // whatever either recipe is retuned to, and names the glyph as the
        // reason `fullLayoutNaturalHeight` went 117 -> 118.
        final double glyphHeight = tester
            .getSize(find.byIcon(Icons.person_outlined))
            .height;
        final double nameHeight = tester
            .getSize(
              find.descendant(
                of: find.byKey(const Key('master-booking-card-natural')),
                matching: find.byType(Text).first,
              ),
            )
            .height;
        expect(
          glyphHeight,
          greaterThan(nameHeight),
          reason:
              'the glyph (${glyphHeight}dp) must out-measure the client name '
              'line box (${nameHeight}dp) — if it does not, the row is back to '
              'being text-driven and fullLayoutNaturalHeight is overstating '
              'the body by the difference',
        );
      },
    );

    // THE 58-MINUTE CASE — retargeted 2026-08-15 (mobile-perf/mobile-security
    // audit of the font-size pass). This group previously pinned 59 minutes,
    // which sat at EXACTLY zero clearance against the pre-pass 118dp
    // threshold. The pass dropped the threshold to 115dp — an odd figure no
    // whole-minute duration lands on exactly — so 59 minutes now clears by
    // 3dp: a test still targeting it would only catch growth beyond that
    // 3dp margin, silently widening this tripwire's blind spot. 58 minutes
    // (`58/60 × 120 = 116dp` floor) is the tightest real edge left — 1dp of
    // clearance over the 115dp natural — and is what this case now pins.
    // See `master_booking_card_layout_height_test.dart`'s sweep, which
    // documents the same 58min/1dp and 59min/3dp figures independently.
    //
    // THIS IS THE TRIPWIRE FOR THE NEXT ADDITIVE CHANGE TO `_buildFullBody`.
    // More than 1dp of growth and a 58-minute booking silently demotes to the
    // compact grid — a real, bookable duration changing shape with nothing to
    // announce it. The divider assertion below turns that into a failure.
    // Written against the DURATION, so it survives a `_kHourH` change the way
    // the layout-height suite's sweep does.
    testWidgets(
      'a 58-minute booking still selects the FULL body — at just 1dp of '
      'clearance, so any growth of that body beyond 1dp fails here',
      (WidgetTester tester) async {
        // `BookingsTimelineGrid._cardMinHeightFor(58)` restated — the same
        // idiom `master_booking_card_layout_height_test.dart` uses, since the
        // scale is private to the grid.
        const double hourHeight = 120; // `BookingsTimelineGrid._kHourH`
        const double floor58 = 58 / 60.0 * hourHeight;

        expect(
          floor58,
          greaterThanOrEqualTo(MasterBookingCard.fullLayoutMinHeight),
          reason:
              'a 58-minute booking derives a ${floor58}dp floor, which no '
              'longer reaches the full-layout switch '
              '(${MasterBookingCard.fullLayoutMinHeight}dp). The full body '
              'grew past the last duration that could contain it — every '
              '58-minute booking has just changed shape. Either give the dp '
              'back, or make the demotion a deliberate, documented decision.',
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: _shortBooking(id: 'fifty-eight', durationMinutes: 58),
                onTap: () {},
                minHeight: floor58,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(
          find.byKey(const Key('master-booking-card-divider-fifty-eight')),
          findsOneWidget,
          reason:
              'a 58-minute booking must still render the FULL divided layout',
        );
        expect(
          find.byKey(
            const Key('master-booking-card-compact-divider-fifty-eight'),
          ),
          findsNothing,
          reason: 'the compact body is the demotion this test exists to catch',
        );
        expect(find.byIcon(Icons.person_outlined), findsOneWidget);

        // 1dp CLEARANCE, STATED AS A MEASUREMENT: box == floor == natural + 1.
        // A box LARGER than the floor would mean the content outgrew the
        // 1dp margin the band allots it and the card overhangs its own
        // end-time line. This is deliberately NOT `closeTo(natural, 0.01)` —
        // the floor (116) sits 1dp above the natural (115) by construction,
        // so the box is pinned to the FLOOR, and it is the floor-vs-natural
        // GAP (asserted below) that is the real tripwire.
        final double height = tester
            .getSize(find.byKey(const Key('master-booking-card-fifty-eight')))
            .height;
        expect(
          height,
          closeTo(floor58, 0.01),
          reason:
              'the 58-minute card measured ${height}dp against its ${floor58}dp '
              'band — they are supposed to coincide, since the floor still '
              'exceeds the natural by 1dp. A larger box is the full body '
              'overhanging the booking\'s end-time line.',
        );
        expect(
          floor58 - MasterBookingCard.fullLayoutNaturalHeight,
          closeTo(1, 0.01),
          reason:
              'the whole point of targeting 58 minutes is that its floor '
              '(${floor58}dp) clears the full body\'s natural '
              '(${MasterBookingCard.fullLayoutNaturalHeight}dp) by only 1dp — '
              'if this gap has grown, a LARGER duration is now the tight '
              'edge and this case should be retargeted at it.',
        );
      },
    );
  });
}

/// Asserts NO date component renders anywhere on the card — the 2026-07-21
/// day-scoped-timeline decision (see `master_booking_card.dart`'s "The time is
/// a RANGE" header section).
///
/// Probes the fixture's own Kyiv short-month token (`лип` for a July booking)
/// via [monthAbbrev] rather than a hard-coded Cyrillic literal: that keeps
/// it clear of the `forbid_cyrillic_finder.sh` gate AND re-derives itself if
/// the fixture's date ever moves. The month is the strongest single probe —
/// the retired «12 лип, 14:30» caption was the ONLY place a date reached this
/// card, and its month token cannot collide with a service name, a client
/// name, a status label or a «₴» price.
///
/// Reads the month through [toBeauticaTime] for the same reason the card
/// does: a booking in the last two hours of a UTC day is already the NEXT
/// Kyiv day, so the raw UTC month is not always the rendered one.
void _expectNoDateOnCard(Booking booking) {
  final String month = monthAbbrev(toBeauticaTime(booking.startAt).month);
  expect(
    find.textContaining(month),
    findsNothing,
    reason:
        'a date component ("$month") reached the card — «Мої записи» is '
        'day-scoped and the day rail above the timeline already names the '
        'day, so the card must print the time range alone.',
  );
}

/// Measured widths of the compact card's TWO flexing labels — row 1's client
/// name and row 2's service name — per lane and per textScaler, with a SINGLE
/// price, minus slack. The "start–end time range" group's per-lane sweep pins
/// these.
///
/// Both labels sit in an `Expanded`, i.e. under a TIGHT width constraint, so
/// each `Text`'s render box reports the share the row allotted it rather than
/// its own intrinsic width.
///
/// Observed:
///
/// | lane | scale | client name | service name |
/// |------|-------|-------------|--------------|
/// | 226  | 1.0   | 118.35dp    | 152.53dp     |
/// | 226  | 1.15  | 108.38dp    | 148.14dp     |
/// | 226  | 1.3   |  98.42dp    | 143.70dp     |
/// | 266  | 1.0   | 158.35dp    | 192.53dp     |
/// | 266  | 1.15  | 148.38dp    | 188.14dp     |
/// | 266  | 1.3   | 138.42dp    | 183.70dp     |
/// | 272  | 1.0   | 164.35dp    | 198.53dp     |
/// | 272  | 1.15  | 154.38dp    | 194.14dp     |
/// | 272  | 1.3   | 144.42dp    | 189.70dp     |
///
/// Every column is exactly the 226dp figure plus the lane's extra width, which
/// is why the floors below are expressed as a base plus [lane] − 226 rather
/// than nine independent literals: the two flexing labels absorb ALL of the
/// extra lane, so a lane-dependent regression (something non-flex growing with
/// width) shows up as a shortfall against the base, not as a missing row in a
/// table.
///
/// Floors carry ~10dp of slack — enough to fail on a real shift, not on
/// sub-pixel font-metric drift.
///
/// A lookup FUNCTION rather than a `Map<double, …>`: Dart bans `double` keys
/// in a const map, and an epsilon comparison is the honest way to match a
/// scale anyway. Returns null for an unmeasured combination so the sweep fails
/// loudly rather than running unpinned.
/// Re-lays out [p]'s own span at the width it was given, reproducing its
/// ellipsis, so the PAINTED line can be measured.
///
/// [RenderParagraph] exposes neither a line count nor a painted-line width
/// directly, so this mirrors `master_result_card_test.dart`'s `_lineCount`
/// idiom — a [TextPainter] re-layout is the only way to reach
/// [TextPainter.computeLineMetrics]. The `ellipsis` argument is what makes
/// the reproduction faithful for a clipping line: without it the painter
/// would lay the full string out and report the untruncated width.
TextPainter _relayout(RenderParagraph p) {
  return TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
  )..layout(maxWidth: p.constraints.maxWidth);
}

/// Width of the first laid-out line of [p] — the GLYPHS, not the box.
double _paintedLineWidth(RenderParagraph p) {
  final TextPainter painter = _relayout(p);
  final double width = painter.computeLineMetrics().first.width;
  painter.dispose();
  return width;
}

/// Number of lines [p] actually laid out.
int _paintedLineCount(RenderParagraph p) {
  final TextPainter painter = _relayout(p);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

({double clientName, double service})? _compactShareFloors(
  double lane,
  double scale,
) {
  const double eps = 0.001;
  if ((lane - 226).abs() > eps &&
      (lane - 266).abs() > eps &&
      (lane - 272).abs() > eps) {
    return null;
  }
  final double laneBonus = lane - 226; // 0 / 40 / 46
  if ((scale - 1.0).abs() < eps) {
    return (clientName: 108 + laneBonus, service: 142 + laneBonus);
  }
  if ((scale - 1.15).abs() < eps) {
    return (clientName: 98 + laneBonus, service: 138 + laneBonus);
  }
  if ((scale - 1.3).abs() < eps) {
    return (clientName: 88 + laneBonus, service: 133 + laneBonus);
  }
  return null;
}

/// Measured service-name widths in the 226dp lane WITH a frozen band, per
/// textScaler, minus slack — the floors the "226dp narrow-lane sweep" pins.
///
/// Observed AFTER the miniature pass (compact figures are the minimum across
/// the realistic and the pathological band, which differ only at scale 1.0
/// where the realistic band stays under the pill's own text cap):
///
/// | textScaler | compact  | full     |
/// |------------|----------|----------|
/// | 1.0        | 87.00dp  | 80.24dp  |
/// | 1.15       | 87.00dp  | 70.73dp  |
/// | 1.3        | 87.00dp  | 61.14dp  |
///
/// THE COMPACT COLUMN ROSE FROM 35/25/15dp TO A FLAT 87dp, and that jump is
/// the whole point of the miniature pass rather than incidental: the price
/// pill left the time row, so row 2's only non-flex child is a self-capping
/// 112dp pill against 203dp of inner width, leaving the service name
/// `203 − 4 (gap) − 112 = 87dp` no matter how wide the band or how large the
/// text scaler. It is flat ACROSS scales for the same reason — the pill's
/// 96dp text cap is an absolute dp constraint, so the scaler moves the
/// `FittedBox`'s scale factor, never the pill's outer width.
///
/// The previous version of this table justified a 15dp floor at scale 1.3 as
/// "small by DESIGN — `_kCompactPriceReserve` budgets only ~15dp of the row to
/// the service name at the ceiling". That justification is retired along with
/// the layout it described; the reserve was re-derived to 68 and no longer
/// binds on any production lane.
///
/// Slack is ~7dp. A lookup FUNCTION rather than a `Map<double, …>`: Dart bans
/// `double` keys in a const map. Returns null for an unmeasured scale so the
/// sweep fails loudly rather than running unpinned.
({double compact, double full})? _narrowServiceFloors(double scale) {
  const double eps = 0.001;
  if ((scale - 1.0).abs() < eps) return (compact: 80, full: 70);
  if ((scale - 1.15).abs() < eps) return (compact: 80, full: 60);
  if ((scale - 1.3).abs() < eps) return (compact: 80, full: 50);
  return null;
}

/// `_PriceTag._maxTextWidth` — private to the widget, restated here so these
/// tests read as an independent check rather than an echo of the source.
const double _kPriceCapWidth = VelvetSpacing.xxl * 2; // 96

Finder get _priceFittedBox => find.descendant(
  of: find.byType(MasterBookingCard),
  matching: find.byType(FittedBox),
);

/// The price band's NATURAL width — `FittedBox` scales by transform, so its
/// child's render box still reports the unscaled size.
double _priceTextWidth(WidgetTester tester) => tester
    .renderObject<RenderBox>(
      find.descendant(of: _priceFittedBox, matching: find.byType(Text)),
    )
    .size
    .width;

/// The width the `ConstrainedBox` actually resolved for the band.
double _fittedPriceWidth(WidgetTester tester) =>
    tester.renderObject<RenderBox>(_priceFittedBox).size.width;

/// The whole price pill's outer width, cap + horizontal padding.
double _priceTagWidth(WidgetTester tester) => tester
    .renderObject<RenderBox>(find.byType(NeumorphicInset).first)
    .size
    .width;
