// The salon «Записи» board paints NO per-column background.
//
// This file used to guard Phase 342's alternating-column wash. That wash is
// gone: it tinted every odd WORKING column with `shadowLightStrong@0.55`
// (composited `#F4EEE4`), which on a real device read as "the masters'
// columns are white" — it showed between and below the opaque cards, and
// because the painter skipped day-off columns it lit up precisely the
// working masters, i.e. the ones carrying cards. It also violated
// `ARCHITECTURE-mobile.md` § 9's locked rule that every surface renders on
// the single warm-taupe base tone and depth is communicated only through
// paired light/dark shadows, never through fills.
//
// The approved preview
// (`docs/signup-designs/SalonBookingsBoard/lib/widgets/
// bookings_timeline_board.dart`, `_GridStack.build`) is the source of truth
// and gives a master column no background at all: [BrandColors.base] runs
// edge to edge behind every column, occupied and empty alike, and lanes are
// separated by the gutter hairline alone — `accent@0.16` there, the value
// this file now pins.
//
// What survives from Phase 342 is the METHOD, not the band: composite before
// you diff. A [ColoredBox]'s `.color` getter returns the raw, un-composited
// token, so diffing it against base is alpha-blind (mutation-tested below).
//
// ── WHAT THIS FILE CANNOT SEE, AND WHERE THAT IS COVERED ──────────────────
//
// Everything here walks WIDGETS: [_boardFills] sweeps `ColoredBox`, and the
// guard below matches one exact `ValueKey`. The wash that actually shipped
// was NEITHER — it was a `CustomPainter` drawing straight to the canvas. So
// this file is structurally blind to a band reintroduced as any painter, or
// as the same painter under a different key.
//
// MEASURED, not inferred (mobile-qa, 2026-09-19): with the band reinstated as
// a `CustomPaint` keyed `'mutant-band'` at the original
// `shadowLightStrong@0.55`, every test in this file stayed GREEN (4/4).
//
// The load-bearing guard is therefore
// `salon_bookings_board_pixel_census_test.dart`, which rasterizes the board
// through `RenderRepaintBoundary.toImage()` and reads the pixels a user
// receives — mechanism-independent by construction. All three of its tests
// went RED on that same mutant. What this file still adds, and that one
// cannot, is the EXACT token+alpha pin on the gutter divider: the divider
// sits in the 6dp gutter, outside every column body the pixel census samples,
// and it DARKENS, so neither the equality rows nor the no-lift sweep fires on
// an alpha drift there (also measured — 0.16 → 0.24 turns the pin below RED
// and leaves the pixel census GREEN). Keep both.
//
// REMOVED WITH THE BAND (nothing else covers them; their subject no longer
// exists):
//   * the whole 'the alternating column wash' group — tint parity, the
//     day-off skip, the single-column no-op, the raw-index numbering;
//   * 'the band LIFTS while a day-off column SINKS' — the lift half is gone;
//     the sink half is generalised into 'nothing on this board LIFTS' below,
//     which is the stronger statement and is what the § 9 rule actually
//     says;
//   * the three-way band/day-off/divider distinguishability table and
//     the band's exported perceptibility floor, which existed only
//     to keep the band visible. The divider is now pinned to an exact token
//     and alpha instead of to a floor — at 0.16 its per-channel deltas off
//     base are (7, 11, 14), deliberately under the old floor of 10, because
//     it is a hairline seam in a 6dp gutter and not a wash.
//
// Column geometry (148dp column, 6dp gutter, 7dp nudge) is the same
// 360dp-viewport, 12dp-padding fixture `salon_bookings_day_off_column_test
// .dart` pins.
//
// CLOCK / TZ: one fixed PAST Kyiv date, colour-only assertions, no real-clock
// predicate read anywhere. `TZ=UTC` changes no expectation.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pixel_census.dart';
import '../../../../helpers/pump_app.dart';

// future-date-ok: fixed PAST Kyiv day; colour-only assertions, no isPast.
final DateTime _day = DateTime(2026, 6, 15);
// future-date-ok: the same fixed PAST day as the canonical UTC instant
final DateTime _dayUtcMidnight = DateTime.utc(2026, 6, 15);

DateTime _kyiv(int hour) => _dayUtcMidnight.add(Duration(hours: hour - 3));

Booking _booking({
  required String id,
  required String masterId,
  int hour = 10,
}) {
  final DateTime start = _kyiv(hour);
  return Booking(
    id: id,
    masterId: masterId,
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

MasterColumnEntry _entry(String id, String name, {bool dayOff = false}) =>
    MasterColumnEntry(
      masterId: id,
      name: name,
      type: MasterType.salonMaster,
      bookingCount: 0,
      professionalTitle: 'Стиліст',
      avgRating: 4.8,
      dayOff: dayOff,
    );

Future<void> _pump(
  WidgetTester tester,
  List<TimelineBoardColumn> columns,
) async {
  await tester.pumpApp(
    // ADDITIVE WRAPPER (LOW-8, 2026-09-20) — a census boundary plus the
    // production ground, so the one assertion in this file that is genuinely
    // about a PIXEL (the gutter divider's rendered tint) can rasterize. Both
    // wrappers are layout pass-throughs, so every widget-walking assertion
    // below sees exactly the tree it always did; `_boardFills` still finds
    // the same `ColoredBox`es because it searches under
    // `BookingsTimelineGrid`, which is inside the wrapper.
    RepaintBoundary(
      key: kCensusBoundary,
      child: ColoredBox(
        color: BrandColors.base,
        child: Padding(
          // Same fixture the day-off column test pins — 360dp viewport, 12dp
          // padding resolves to a 148dp column / 6dp gutter / 7dp nudge.
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: BookingsTimelineGrid(
            bookings: <Booking>[
              for (final TimelineBoardColumn c in columns) ...c.bookings,
            ]..sort((Booking a, Booking b) => a.startAt.compareTo(b.startAt)),
            day: _day,
            onBookingTap: (_) {},
            density: TimelineDensity.salon,
            columns: columns,
          ),
        ),
      ),
    ),
    width: 360,
    height: 600,
  );
  await tester.pump();
}

int _channel8(double component) => (component * 255).round().clamp(0, 255);

/// A [ColoredBox]'s `.color` getter returns the RAW, un-composited token —
/// its own stored RGB channels plus an alpha byte, NOT the blended pixel a
/// user's eye receives once that alpha is painted over whatever sits behind
/// it. Reading `.r`/`.g`/`.b` off that raw token ignores alpha entirely:
/// `_columnDividerColor` at 0.16 and at 0.24 are the SAME source token
/// ([BrandColors.accent]) with two different alphas, so an uncomposited diff
/// against base is IDENTICAL at both and cannot distinguish them —
/// mutation-tested: asserting on the raw `.color` stayed green at both.
/// [Color.alphaBlend] performs the real src-over composite, so channel math
/// after this call reflects the pixel actually rendered.
Color _composited(Color src) => Color.alphaBlend(src, BrandColors.base);

/// Every [ColoredBox] the board built, as the composited pixel it produces
/// over [BrandColors.base]. The board's fills — the day-off wash, the hour
/// and half-hour gridlines, the gutter dividers, the «зараз» hairline — are
/// all `ColoredBox`es, which is what makes this sweep a real census of the
/// board's flat WIDGET fills rather than a spot check of the ones a test
/// happened to key.
///
/// It is NOT a census of what the board PAINTS: a `CustomPainter` contributes
/// nothing a `widgetList` can find, and that is precisely the mechanism the
/// removed band used. See this file's header — the pixel-level census lives
/// in `salon_bookings_board_pixel_census_test.dart`.
Iterable<Color> _boardFills(WidgetTester tester) {
  return tester
      .widgetList<ColoredBox>(
        find.descendant(
          of: find.byType(BookingsTimelineGrid),
          matching: find.byType(ColoredBox),
        ),
      )
      .map((ColoredBox box) => _composited(box.color));
}

void main() {
  group('the salon board paints no column background', () {
    testWidgets(
      'builds no alternating-column wash — the removed widget is not back',
      (WidgetTester tester) async {
        await _pump(tester, <TimelineBoardColumn>[
          TimelineBoardColumn(
            header: _entry('m1', 'Оля Коваль'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m2', 'Ніна Бойко'),
            bookings: <Booking>[_booking(id: 'b1', masterId: 'm2', hour: 10)],
          ),
          TimelineBoardColumn(
            header: _entry('m3', 'Іра Ткач'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m4', 'Настя Гриб'),
            bookings: <Booking>[_booking(id: 'b2', masterId: 'm4', hour: 12)],
          ),
        ]);

        // Occupied AND empty columns are both on the board — the defect the
        // user saw was read as "the columns with a booking are white", so the
        // fixture must contain both kinds for the sweep below to mean
        // anything.
        expect(
          find.byKey(const ValueKey<String>('timeline-card-b1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-b2')),
          findsOneWidget,
        );

        expect(
          find.byKey(
            const ValueKey<String>('timeline-alternating-column-wash'),
          ),
          findsNothing,
          reason:
              'a master column has no background of its own — the approved '
              'preview lets BrandColors.base run behind every column',
        );
      },
    );

    testWidgets(
      'no fill on the board LIFTS above the base tone — § 9 forbids depth by '
      'fill, and a lifting fill is exactly how the near-white columns shipped',
      (WidgetTester tester) async {
        await _pump(tester, <TimelineBoardColumn>[
          TimelineBoardColumn(
            header: _entry('m1', 'Оля Коваль'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m2', 'Ніна Бойко'),
            bookings: <Booking>[_booking(id: 'b1', masterId: 'm2', hour: 10)],
          ),
          // A day-off column too, so its wash is inside the census and this
          // test also pins that the ONE documented column state still sinks.
          TimelineBoardColumn(
            header: _entry('m3', 'Іра Ткач', dayOff: true),
            bookings: const <Booking>[],
          ),
        ]);

        const Color base = BrandColors.base;
        final List<Color> fills = _boardFills(tester).toList();
        expect(
          fills,
          isNotEmpty,
          reason:
              'the sweep must actually find the board fills — an empty list '
              'would make every assertion below vacuous',
        );

        for (final Color fill in fills) {
          // No channel may sit ABOVE base. Mutation-
          // tested — restoring the band as a lifting `ColoredBox`, or
          // re-tinting any wash with BrandColors.shadowLightStrong, turns
          // this red.
          expect(
            _channel8(fill.r),
            lessThanOrEqualTo(_channel8(base.r)),
            reason: 'a board fill lifted the red channel above base: $fill',
          );
          expect(
            _channel8(fill.g),
            lessThanOrEqualTo(_channel8(base.g)),
            reason: 'a board fill lifted the green channel above base: $fill',
          );
          expect(
            _channel8(fill.b),
            lessThanOrEqualTo(_channel8(base.b)),
            reason: 'a board fill lifted the blue channel above base: $fill',
          );
        }

        // And the day-off wash — the one legitimate column state — is still
        // strictly darker, not merely not-lighter.
        final Color dayOff = _composited(
          tester
              .widget<ColoredBox>(
                find.byKey(
                  const ValueKey<String>('timeline-column-day-off-wash-2'),
                ),
              )
              .color,
        );
        expect(_channel8(dayOff.r), lessThan(_channel8(base.r)));
        expect(_channel8(dayOff.g), lessThan(_channel8(base.g)));
        expect(_channel8(dayOff.b), lessThan(_channel8(base.b)));
      },
    );
  });

  group('the gutter divider', () {
    testWidgets(
      'is BrandColors.accent at alpha 0.16 — the approved preview\'s value, '
      'not Phase 342\'s 0.24',
      (WidgetTester tester) async {
        await _pump(tester, <TimelineBoardColumn>[
          TimelineBoardColumn(
            header: _entry('m1', 'Оля Коваль'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m2', 'Ніна Бойко'),
            bookings: const <Booking>[],
          ),
        ]);

        final ColoredBox divider = tester.widget<ColoredBox>(
          find.byKey(const ValueKey<String>('timeline-column-divider-1')),
        );

        // Pinned to the exact token+alpha the preview draws
        // (`bookings_timeline_board.dart`'s column-separator loop:
        // `VelvetColors.accent.withValues(alpha: 0.16)`). Phase 342 had
        // raised this to 0.24 purely to hold its own against the band; with
        // the band gone the compensation goes with it, and this equality is
        // what stops the alpha drifting again unnoticed — `isNot(base)` or a
        // delta floor would both stay green at 0.24.
        expect(
          divider.color,
          BrandColors.accent.withValues(alpha: 0.16),
          reason: 'the divider must match the approved preview exactly',
        );
      },
    );

    testWidgets('sinks below base on every channel, and is the only thing '
        'separating two working lanes', (WidgetTester tester) async {
      await _pump(tester, <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль'),
          bookings: const <Booking>[],
        ),
        TimelineBoardColumn(
          header: _entry('m2', 'Ніна Бойко'),
          bookings: const <Booking>[],
        ),
      ]);

      const Color base = BrandColors.base;
      final Color divider = _composited(
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey<String>('timeline-column-divider-1')),
            )
            .color,
      );

      expect(_channel8(divider.r), lessThan(_channel8(base.r)));
      expect(_channel8(divider.g), lessThan(_channel8(base.g)));
      expect(_channel8(divider.b), lessThan(_channel8(base.b)));

      // ── AND IT ACTUALLY PAINTS (LOW-8, 2026-09-20) ────────────────────
      //
      // Everything above this point reads a WIDGET FIELD, which this file's
      // header is explicit about: a divider configured correctly and then
      // overpainted, clipped, or drawn under an `Opacity` keeps every one of
      // those assertions green. One rasterised sample closes that for the
      // divider specifically, through the same
      // `RenderRepaintBoundary.toImage()` recipe
      // `salon_bookings_board_pixel_census_test.dart` uses (promoted to
      // `test/helpers/pixel_census.dart` so neither file owns a private copy).
      //
      // TOTAL INK down a horizontal band, not one sample: the divider is 1dp
      // wide at a `columnPitch − gutter / 2` offset that need not land on a
      // pixel boundary, so summing `base − pixel` across a band wider than
      // the rule is the coverage-independent reading.
      final Raster raster = await rasterize(tester);
      final Rect dividerRect = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-column-divider-1')),
      );
      final double y = dividerRect.center.dy;
      double ink(int Function((int, int, int)) pick, int baseChannel) {
        double total = 0;
        for (
          double x = dividerRect.left - 2;
          x < dividerRect.left + 3;
          x += 1
        ) {
          total += baseChannel - pick(raster.at(x, y));
        }
        return total;
      }

      expect(
        ink((c) => c.$1, _channel8(base.r)),
        closeTo(_channel8(base.r) - _channel8(divider.r), 2),
        reason:
            'the gutter divider must actually rasterize as accent@0.16 over '
            'base — a divider that paints nothing reads ~0 ink here while '
            'every field read above stays green',
      );
      expect(
        ink((c) => c.$3, _channel8(base.b)),
        closeTo(_channel8(base.b) - _channel8(divider.b), 2),
      );

      // Two working masters, no day-off wash, no band: the divider is the
      // whole separation story on this board.
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-alternating-column-wash')),
        findsNothing,
      );
    });
  });
}
