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
//   row 1  start–end range · client name (flexes) · status DOT
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
//   * The vertical budget is now EXACT — 41dp of content in a 56dp box at
//     textScaler 1.0, zero slack — where the outgoing layout measured 55dp
//     against the same 56 and carried ~1dp of slop. The "41dp vertical
//     budget" group below is new: the previous suite only ever guarded
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
//     `kMonthsUkShort` token rather than a Cyrillic literal, so it survives
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
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
  // overflow floor), and the `kMonthsUkShort` no-date probe in
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
          // 30-minute slot (56dp — `bookings_timeline_grid.dart`'s `_kSlotH`),
          // i.e. every row above genuinely contributed to layout rather than
          // being painted then cropped away. No `minHeight` is passed here —
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
        // `minHeight` that large would trip the >=112dp full-layout switch
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

          // …and the time LEADS the client name on row 1 (the lighter label
          // before the heavier one — see `_buildCompactBody`'s row-1 comment on
          // why that reads as a sentence rather than two table cells).
          expect(
            tester.getTopLeft(timeFinder).dx,
            lessThan(tester.getTopLeft(find.text(booking.clientName!)).dx),
          );
        },
      );
    },
  );

  // NEW IN THE MINIATURE PASS — the previous suite guarded WIDTH only.
  //
  // The compact layout is sized TO its box rather than measured after the
  // fact: at textScaler 1.0 a 56dp card leaves `56 − 3 (border 1.5 × 2) − 12
  // (`_compactPadding` vertical 6 × 2) = 41dp` of content, and the stack
  // spends all 41 —
  //
  //   row 1 (15, client name) + gap (4) + hairline (1) + gap (4)
  //   + row 2 (17, the price pill: a 15dp line box + 1dp padding × 2) = 41
  //
  // — with ZERO slack. That is the whole reason the pill's vertical padding
  // was cut 3 -> 1 (`_kCompactPriceVPad`): those 4dp bought the hairline and
  // its two gaps. A regression that restores the padding, widens a gap or
  // adds a row therefore OVERFLOWS the slot instead of silently eating room
  // that was never there, and these cases are what make that visible.
  group('the 41dp vertical budget — the compact card fits its 56dp slot', () {
    testWidgets(
      'the natural height is EXACTLY MasterBookingCard.estimatedNaturalHeight '
      '(56dp) at textScaler 1.0',
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
              'slack: the 41dp content budget is fully spent (see the group '
              'header). If this moved, either the layout grew — in which case '
              'a 30-minute card no longer fits its own ruled slot and '
              '_LaneColumn goes back to nudging cards off their hour line — '
              'or it shrank, in which case estimatedNaturalHeight and its '
              'derivation comment are now lying to bookings_timeline_grid.',
        );
      },
    );

    // The vertical fit, asserted the way the timeline actually applies it: a
    // real `minHeight: 56` floor. If the content out-measured the box the
    // card would grow PAST 56 (minHeight is a floor, never a ceiling — see
    // the widget's class doc), so an exact-56 result is a direct proof of
    // fit, not an approximation of one.
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
          '${shape.label} fits a 56dp box in the ${lane.toInt()}dp lane '
          '(textScaler 1.0)',
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
                    minHeight: 56,
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
              56,
              reason:
                  'the card grew to ${height}dp inside a 56dp slot — the '
                  'content out-measures the 41dp budget, so a 30-minute '
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
        // Measured naturals: 56.0 / 60.0 / 65.0 at 1.0 / 1.15 / 1.3. The 56dp
        // slot is a scale-1.0 budget by construction (the type scales, the
        // ruler does not), so the correct behaviour above 1.0 is a taller
        // card, exactly as the outgoing layout did.
        double previous = 0;
        for (final double scale in <double>[1.0, 1.15, 1.3]) {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: _shortBooking(id: 'vgrow'),
                  onTap: () {},
                  minHeight: 56,
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
            greaterThanOrEqualTo(56),
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
                minHeight: 112,
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
              (label: 'full', minHeight: 112, duration: 60),
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

        final double compact = await pillHeight(56, 30);
        final double full = await pillHeight(112, 60);

        // 15dp line box + 3dp × 2 in the full layout, + 1dp × 2 in the compact
        // one. The FULL figure is the design's own `PriceTag` value and must
        // not move: `_PriceTag.verticalPadding` defaults to 3 precisely so the
        // >=1h card renders byte-identically to before this pass.
        expect(
          full,
          21,
          reason:
              'the FULL layout\'s price pill measured ${full}dp — it must stay '
              'at the approved design\'s 21dp (15dp line + 3dp padding × 2). '
              'The compact layout\'s padding cut must not have leaked into the '
              'shared default.',
        );
        expect(
          compact,
          17,
          reason:
              'the COMPACT pill measured ${compact}dp — the 1dp padding is '
              'what pays for the hairline and its two gaps inside the 41dp '
              'budget.',
        );
        expect(full - compact, 4);
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
      // row 1 narrower — the height is the same 56dp budget.
      final double height = tester
          .getSize(find.byKey(const Key('master-booking-card-guest-card')))
          .height;
      expect(height, MasterBookingCard.estimatedNaturalHeight);
    });
  });

  group(
    'adaptive full/compact layout (2026-07-20 design-parity pass) — the '
    'switch reads the resolved minHeight constraint, not durationMinutes',
    () {
      testWidgets(
        'a >=112dp card (a 60-minute booking\'s floor) renders the FULL '
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
                minHeight: 112,
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
        'a 56dp card (the 30-minute floor) stays on the compact grid — its '
        'own hairline, a status dot, no date — and still renders every field '
        'un-clipped',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking(
            id: 'compact-floor-card',
            durationMinutes: 30,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 56,
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
          expect(height, closeTo(56, 0.5));
        },
      );

      testWidgets(
        'MUTATION CHECK — forcing the compact layout at every height makes '
        'the full-layout divider assertion fail; the real code must NOT '
        'exhibit this failure',
        (WidgetTester tester) async {
          // This test intentionally re-runs the FIRST test's own divider
          // assertion against a card whose `minHeight` is comfortably past
          // the >=112dp threshold, as a standing structural guard: it is
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
                minHeight: 168,
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
                'a 168dp (90-minute) card must select the FULL layout — if '
                'this fails, the height-vs-threshold switch in '
                'MasterBookingCard.build has regressed to always picking '
                'the compact body.',
          );
          expect(find.byType(TimelineStatusBadge), findsOneWidget);
        },
      );
    },
  );

  // THE 45-MINUTE QUESTION (2026-07-21) — evidence for `_kFullLayoutMinHeight`
  // staying at 112 rather than dropping to 84.
  //
  // A 45-minute booking's duration-derived floor is 84dp (`45/60 × _kHourH`,
  // `bookings_timeline_grid.dart`), half again the compact card's own box, so
  // "surely the full layout fits by now" is the obvious next edit. It does
  // not, and this group is the rendered proof rather than a comment asserting
  // it. `_buildFullBody`'s NATURAL height, measured with the worst realistic
  // content (a long service name and a frozen RANGE band) at the narrowest
  // production lane:
  //
  //   | textScaler | natural |
  //   |------------|---------|
  //   | 1.0        | 117.0dp |
  //   | 1.15       | 124.0dp |
  //   | 1.3        | 132.0dp |
  //
  // Identical at 226 / 266 / 272dp of lane — every row in that body is
  // flex-driven, so lane width moves the ellipsis, never the height. The
  // measurement is EXACT rather than a lower bound because all three exceed
  // the 112dp floor the card is pumped with, so the box is sized by content.
  //
  // 117 > 84 by 33dp at scale 1.0 and by 48dp at the app's 1.3 ceiling: a
  // 45-minute card on the full layout would render ~1.4× the ruled space its
  // duration owns, which is precisely the "cards drift off their hour line"
  // regression the compact-timeline pass existed to remove.
  group('the 45-minute question — why _kFullLayoutMinHeight stays at 112', () {
    for (final double scale in <double>[1.0, 1.15, 1.3]) {
      testWidgets(
        'the FULL body\'s natural height overshoots an 84dp box (textScaler '
        '$scale)',
        (WidgetTester tester) async {
          final Booking booking =
              _shortBooking(id: 'full-natural', durationMinutes: 60).copyWith(
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
                  minHeight: 112,
                ),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('master-booking-card-divider-full-natural')),
            findsOneWidget,
            reason: 'precondition: this must be the FULL layout',
          );

          final double natural = tester
              .getSize(
                find.byKey(const Key('master-booking-card-full-natural')),
              )
              .height;

          // Strictly greater than the pumped floor, so this IS the content's
          // own height and not the constraint's.
          expect(
            natural,
            greaterThan(112),
            reason:
                'the full body measured ${natural}dp — at or under the 112dp '
                'floor it was pumped with, so this number is the CONSTRAINT '
                'rather than the content and the overshoot below proves '
                'nothing. Re-measure with a lower floor.',
          );
          expect(
            natural,
            greaterThan(84 + 30),
            reason:
                'the full body measured ${natural}dp against an 84dp '
                '45-minute slot. If this ever drops near 84, re-run the '
                'measurement table in this group\'s header and only THEN '
                'consider lowering _kFullLayoutMinHeight.',
          );
        },
      );
    }

    testWidgets(
      'a 45-minute card (84dp) therefore selects the COMPACT layout, and fits '
      'inside its slot with room to spare',
      (WidgetTester tester) async {
        final Booking booking =
            _shortBooking(id: 'forty-five', durationMinutes: 45).copyWith(
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
                minHeight: 84,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(
            const Key('master-booking-card-compact-divider-forty-five'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-booking-card-divider-forty-five')),
          findsNothing,
        );
        expect(
          tester
              .getSize(find.byKey(const Key('master-booking-card-forty-five')))
              .height,
          84,
          reason:
              'the 84dp floor must be met exactly — the compact body\'s 56dp '
              'of content leaves 28dp of blank room below it, which is the '
              'intended "the card fills the slot its duration occupies" '
              'behaviour, not an overflow.',
        );
      },
    );

    // The threshold's exact boundary, so a future off-by-one (>= vs >) is a
    // failure rather than a silently different card on 60-minute bookings.
    for (final ({double minHeight, bool full}) boundary
        in <({double minHeight, bool full})>[
          (minHeight: 111, full: false),
          (minHeight: 112, full: true),
        ]) {
      testWidgets('minHeight ${boundary.minHeight} selects the '
          '${boundary.full ? 'FULL' : 'COMPACT'} layout', (
        WidgetTester tester,
      ) async {
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
          (label: 'full', minHeight: 112),
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
                  minHeight: 112,
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

    testWidgets('the full layout (>=112dp) renders the band too', (
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
            minHeight: 112,
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
              (label: 'full', minHeight: 112, duration: 60),
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
  // but does not fail on:
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
      'the 15dp of chrome and the 41dp of content are separately pinned, and '
      'the content stack spends 15 + 4 + 1 + 4 + 17',
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
        // Row 1's tallest child IS the row (the range label is 13.8dp and the
        // dot 8dp against the name's 15dp, under `CrossAxisAlignment.center`),
        // and row 2's tallest child is the pill — so these two rects delimit
        // the content region exactly.
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
              'Either _kBorderWidth or _compactPadding moved and the 41dp '
              'budget derivation on estimatedNaturalHeight is now wrong.',
        );
        expect(
          card.bottom - pill.bottom,
          closeTo(7.5, 0.01),
          reason: 'the bottom chrome must mirror the top exactly',
        );

        // ── THE CONTENT: 41dp, and the five terms that spend it. ─────────────
        expect(
          pill.bottom - name.top,
          closeTo(41, 0.01),
          reason:
              'the content region measured ${pill.bottom - name.top}dp against '
              'the documented 41dp budget',
        );
        for (final ({String label, double actual, double expected}) term
            in <({String label, double actual, double expected})>[
              (
                label: 'row 1 (the client name)',
                actual: name.height,
                expected: 15,
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
                label: 'row 2 (the price pill, 15dp line + 1dp padding × 2)',
                actual: pill.height,
                expected: 17,
              ),
            ]) {
          expect(
            term.actual,
            closeTo(term.expected, 0.01),
            reason:
                '${term.label} measured ${term.actual}dp against its budgeted '
                '${term.expected}dp. The card still fits 56dp only because '
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
    // existing pill test proves the PILL is 21dp in the full layout; this
    // proves the full BODY's own height did not move either. Exact, not a
    // floor — "the >=1h card renders byte-identically" is the claim, and a
    // floor cannot express it.
    for (final ({double scale, double height}) fullNatural
        in <({double scale, double height})>[
          (scale: 1.0, height: 117),
          (scale: 1.15, height: 124),
          (scale: 1.3, height: 132),
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
                  // The card's own natural height, not a floor that could mask
                  // it — 1 is below every layout's content, and the switch
                  // reads `minHeight`, so the FULL body must be selected
                  // explicitly instead.
                  minHeight: 112,
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
          final ({Color accent, String label}) badge = await render(112, 60);

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

  // `_kCompactPriceReserve` (68) does not bind on ANY lane the timeline can
  // build — 226dp of lane is 203dp of row, so the cap resolves to 135dp,
  // above `_PriceTag`'s own 112dp ceiling. That is documented on the constant
  // and is the honest state of things; what it left behind is a constant
  // NOTHING fails on: 0 and 130 render identically to 68 at every production
  // width. This exercises it at the width where it genuinely engages, so the
  // number is a commitment rather than a free parameter — and the assertion is
  // its stated PURPOSE (the ~64dp readable service-name sliver), not the
  // literal, so a wrong reserve fails with the sliver it cost.
  group('_kCompactPriceReserve binds below the production floor', () {
    testWidgets(
      'on a sub-production 190dp lane the pill yields exactly the documented '
      '64dp sliver to the service name',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(id: 'reserve').copyWith(
          serviceName: 'Комплексний догляд за волоссям з ботоксом та укладкою',
          price: 1234567,
          priceMax: 8901234,
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 190,
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        // The hairline is full-bleed inside the padding, so its width IS the
        // row width the `LayoutBuilder` resolved — read rather than re-derived
        // from the lane, so a padding change cannot silently shift the target.
        final double row = tester
            .getSize(
              find.byKey(
                const Key('master-booking-card-compact-divider-reserve'),
              ),
            )
            .width;
        final double pill = _priceTagWidth(tester);
        final double service = tester
            .renderObject<RenderBox>(find.text(booking.serviceName))
            .size
            .width;

        expect(
          row,
          lessThan(180),
          reason:
              'precondition: the cap only engages below a ~180dp row — above '
              'it the pill\'s own 112dp ceiling binds first and this test '
              'proves nothing about the reserve',
        );
        expect(
          pill,
          closeTo(row - 68, 0.01),
          reason:
              'the pill measured ${pill}dp on a ${row}dp row — the compact '
              'cap is `row − _kCompactPriceReserve`, so this is the reserve '
              'read back out of the layout',
        );
        expect(
          service,
          closeTo(64, 0.01),
          reason:
              'the service name kept ${service}dp — the reserve exists to '
              'leave it 64dp (a readable ~5-6 Cyrillic glyphs plus the '
              'ellipsis) after the row\'s single 4dp gap. A reserve of 0 hands '
              'the pill its full 112dp ceiling and leaves ~51dp here; a larger '
              'one starves the pill instead.',
        );
        // The band is scaled, never clipped or ellipsised, even squeezed.
        expect(find.text(booking.priceLabel), findsOneWidget);
      },
    );
  });
}

/// Asserts NO date component renders anywhere on the card — the 2026-07-21
/// day-scoped-timeline decision (see `master_booking_card.dart`'s "The time is
/// a RANGE" header section).
///
/// Probes the fixture's own Kyiv short-month token (`лип` for a July booking)
/// via [kMonthsUkShort] rather than a hard-coded Cyrillic literal: that keeps
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
  final String month =
      kMonthsUkShort[toBeauticaTime(booking.startAt).month - 1];
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
