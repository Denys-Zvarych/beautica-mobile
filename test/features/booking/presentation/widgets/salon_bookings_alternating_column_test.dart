// Phase 342 — the salon «Записи» board's alternating-column wash.
//
// The user could not tell which column belonged to which master while
// scanning the board, and the fix (see `bookings_timeline_grid.dart`'s
// "THE ALTERNATING COLUMN WASH" comment) is a single `CustomPainter` pass
// that tints every ODD, WORKING master column with a subtle recess band —
// deliberately not one [Positioned]/[ColoredBox] per tinted column, unlike
// the day-off wash next door, because this board already carries a
// mobile-perf HIGH about a `SingleChildScrollView` painting its whole child;
// a second per-column widget would multiply exactly that layer count.
//
// Because there is no per-column `Key` to find (that is the whole point —
// ONE painter, not N widgets), this file rasterises the real painter
// instance the widget tree built — obtained from `CustomPaint.painter`, not
// constructed by the test — onto its own `Canvas`/`Image` and reads pixels
// back. That exercises the actual `paint()` the framework would call, not a
// restatement of it, and needs no golden baseline (none exists for this
// widget — see the file's own "NO GOLDENS ON THIS WIDGET" note).
//
// Column geometry (148dp column, 6dp gutter, 7dp nudge) is the same
// 360dp-viewport, 12dp-padding fixture `salon_bookings_day_off_column_test
// .dart` already pins to the pixel — reused verbatim so this file cannot
// silently drift onto a different board shape.
//
// CLOCK / TZ: one fixed PAST Kyiv date, geometry-only assertions, no
// real-clock predicate read anywhere. `TZ=UTC` changes no expectation.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// future-date-ok: fixed PAST Kyiv day; geometry-only assertions, no isPast.
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
    Padding(
      // Same fixture the day-off column test pins — 360dp viewport, 12dp
      // padding resolves to a 148dp column / 6dp gutter / 7dp nudge, so the
      // pixel math below is derived, not guessed.
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
    width: 360,
    height: 600,
  );
  await tester.pump();
}

/// Rasterises the board's real, rendered [CustomPainter] onto its own
/// surface and returns the pixel colour at column [index]'s centre, `12dp`
/// below the wash's own top edge (`nudge`) — inside every column's band
/// regardless of that column's content.
Future<Color> _paintedColorAt(WidgetTester tester, int index) async {
  const double columnWidth = 148;
  const double gutter = 6;
  const double columnPitch = columnWidth + gutter;
  const double nudge = 7;

  final Finder finder = find.byKey(
    const ValueKey<String>('timeline-alternating-column-wash'),
  );
  final CustomPaint customPaint = tester.widget<CustomPaint>(finder);
  final CustomPainter? painter = customPaint.painter;
  expect(
    painter,
    isNotNull,
    reason: 'the board must have built the wash painter',
  );
  final Size size = tester.getSize(finder);

  // `Picture.toImage` / `Image.toByteData` do real engine-side raster work
  // that never completes inside `testWidgets`' fake-async zone — it must run
  // under `tester.runAsync` or the awaited `Future`s simply never resolve
  // (observed: a 10-minute `TimeoutException` per call before this fix).
  final Color? sampled = await tester.runAsync<Color>(() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    // A known background so "untouched" and "tinted" are distinguishable —
    // BrandColors.base, the exact tone the wash sits on top of in the app.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = BrandColors.base,
    );
    painter!.paint(canvas, size);
    final ui.Image image = await recorder.endRecording().toImage(
      size.width.ceil(),
      size.height.ceil(),
    );
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(bytes, isNotNull);

    final double x = index * columnPitch + columnWidth / 2;
    const double y = nudge + 12;
    final int px = x.round().clamp(0, image.width - 1);
    final int py = y.round().clamp(0, image.height - 1);
    final int offset = (py * image.width + px) * 4;
    final Uint8List rgba = bytes!.buffer.asUint8List();
    return Color.fromARGB(
      rgba[offset + 3],
      rgba[offset],
      rgba[offset + 1],
      rgba[offset + 2],
    );
  });
  expect(sampled, isNotNull);
  return sampled!;
}

/// The largest per-channel gap between [a] and [b]'s RGB components,
/// mirroring how a human eye judges "is this actually a different colour"
/// far better than an exact-value `expect(c, isNot(base))` does — that
/// assertion is satisfied by a 1/255 nudge, which is exactly how the
/// original band shipped invisible while every exact-value test stayed
/// green. See `bookings_timeline_grid.dart`'s [kAlternatingBandMinDelta]
/// doc for the incident this guards against.
int _channel8(double component) => (component * 255).round().clamp(0, 255);

int _maxChannelDelta(Color a, Color b) {
  final int dr = (_channel8(a.r) - _channel8(b.r)).abs();
  final int dg = (_channel8(a.g) - _channel8(b.g)).abs();
  final int db = (_channel8(a.b) - _channel8(b.b)).abs();
  return <int>[dr, dg, db].reduce((int x, int y) => x > y ? x : y);
}

/// The SMALLEST per-channel gap — deliberately distinct from
/// [_maxChannelDelta] above. `kAlternatingBandMinDelta`'s own doc comment
/// in `bookings_timeline_grid.dart` says the floor must clear "per RGB
/// channel", and the divider's doc comment there names a concrete case
/// that only makes sense under that reading: the old 0.16 alpha's R-channel
/// delta of 7 is what it calls out as failing the floor. A max-based check
/// does NOT catch that regression — mutation-tested here: reverting the
/// divider to alpha 0.16 (channel deltas 7/11/14) leaves
/// `_maxChannelDelta` at 14, which still clears a floor of 10, so a
/// max-based assertion stays green on exactly the value this guard exists
/// to reject. Min-channel is what actually enforces "every channel, not
/// just the strongest one" — used for every NEW Phase 342-hardening
/// assertion below.
int _minChannelDelta(Color a, Color b) {
  final int dr = (_channel8(a.r) - _channel8(b.r)).abs();
  final int dg = (_channel8(a.g) - _channel8(b.g)).abs();
  final int db = (_channel8(a.b) - _channel8(b.b)).abs();
  return <int>[dr, dg, db].reduce((int x, int y) => x < y ? x : y);
}

/// A [ColoredBox]'s `.color` getter returns the RAW, un-composited token —
/// its own stored RGB channels plus an alpha byte, NOT the blended pixel a
/// user's eye actually receives once that alpha is painted over whatever
/// sits behind it. Reading `.r`/`.g`/`.b` off that raw token and diffing it
/// against [BrandColors.base] ignores alpha entirely: `_columnDividerColor`
/// at alpha 0.16 and at 0.24 are the SAME source token
/// ([BrandColors.accent]) with two different alphas, so an uncomposited
/// diff against base is IDENTICAL at both alphas and cannot distinguish
/// them — mutation-tested: asserting on the raw `.color` stayed green at
/// both 0.16 and 0.24, proving it is alpha-blind. [Color.alphaBlend]
/// performs the real src-over composite (the same maths the production
/// doc comments compute by hand, e.g. accent@0.24 -> `#DBCDBB`), so
/// delta math after this call reflects the pixel actually rendered, not
/// the token that produced it.
Color _composited(Color src) => Color.alphaBlend(src, BrandColors.base);

void main() {
  group('the alternating column wash', () {
    testWidgets('tints every odd WORKING column and leaves even columns bare', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль'),
          bookings: const <Booking>[],
        ),
        TimelineBoardColumn(
          header: _entry('m2', 'Ніна Бойко'),
          bookings: const <Booking>[],
        ),
        TimelineBoardColumn(
          header: _entry('m3', 'Іра Ткач'),
          bookings: const <Booking>[],
        ),
        TimelineBoardColumn(
          header: _entry('m4', 'Настя Гриб'),
          bookings: const <Booking>[],
        ),
      ]);

      final Color c0 = await _paintedColorAt(tester, 0);
      final Color c1 = await _paintedColorAt(tester, 1);
      final Color c2 = await _paintedColorAt(tester, 2);
      final Color c3 = await _paintedColorAt(tester, 3);

      expect(c0, BrandColors.base, reason: 'even column 0 stays bare');
      expect(c2, BrandColors.base, reason: 'even column 2 stays bare');
      expect(c1, isNot(BrandColors.base), reason: 'odd column 1 is tinted');
      expect(c3, isNot(BrandColors.base), reason: 'odd column 3 is tinted');
      // Both odd columns read the same tint — one shared token, not one per
      // column.
      expect(c1, c3);

      // PERCEPTIBILITY, not merely presence. `isNot(BrandColors.base)` above
      // is satisfied by a 1/255 nudge — exactly how the band originally
      // shipped invisible on a real phone while every exact-value pixel
      // test stayed green (see `kAlternatingBandMinDelta`'s doc in
      // `bookings_timeline_grid.dart`). This is the assertion whose absence
      // let that ship; without it, a future alpha regression back toward
      // `BrandColors.base` would pass every other check here.
      expect(
        _maxChannelDelta(c1, BrandColors.base),
        greaterThanOrEqualTo(kAlternatingBandMinDelta),
        reason:
            'the tinted column must be perceptibly different from the '
            'base surface, not just technically unequal',
      );
    });

    testWidgets('an OFF column keeps its grey and never also gets the tint', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль'),
          bookings: const <Booking>[],
        ),
        // Column 1 is odd (would be tinted) AND off — day-off must win.
        TimelineBoardColumn(
          header: _entry('m2', 'Ніна Бойко', dayOff: true),
          bookings: const <Booking>[],
        ),
      ]);

      // The day-off wash still exists, unaffected.
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-1')),
        findsOneWidget,
      );
      // The alternating-band PAINTER itself paints nothing over column 1 —
      // measured directly on the painter's own output, independent of the
      // day-off `ColoredBox` that sits over it in the live tree.
      final Color c1 = await _paintedColorAt(tester, 1);
      expect(
        c1,
        BrandColors.base,
        reason: 'the painter skips a day-off column entirely',
      );
    });

    testWidgets(
      'still tints an odd column that carries real bookings — the wash is '
      'not only visible on an empty column',
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
        ]);

        expect(
          find.byKey(const ValueKey<String>('timeline-card-b1')),
          findsOneWidget,
          reason: 'the booking must actually be on the board',
        );
        final Color c1 = await _paintedColorAt(tester, 1);
        expect(
          c1,
          isNot(BrandColors.base),
          reason:
              'the band paints under the card too, not only on empty '
              'columns',
        );
      },
    );

    testWidgets('a single-column board paints no band at all', (
      WidgetTester tester,
    ) async {
      // `for (int i = 1; i < columnCount; i += 2)` never runs when
      // columnCount == 1 — there is nothing to alternate against. Pins that
      // an off-by-one on the loop bound (e.g. `i = 0`) cannot silently tint
      // the only column on a one-master salon's board.
      await _pump(tester, <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль'),
          bookings: const <Booking>[],
        ),
      ]);

      final Color c0 = await _paintedColorAt(tester, 0);
      expect(c0, BrandColors.base, reason: 'the sole column stays bare');
    });

    testWidgets(
      'a day-off column in the middle does not renumber the columns after '
      'it — parity is the raw slot index, not the non-day-off count',
      (WidgetTester tester) async {
        // Columns: m1(work,0) m2(OFF,1) m3(work,2) m4(work,3).
        //
        // Slot-index parity (the shipped behaviour): 0 bare, 1 skipped
        // (day-off), 2 bare (even), 3 tinted (odd).
        //
        // If banding instead counted only non-day-off columns (renumbering
        // m3 -> 1, m4 -> 2), the result would flip: m3 tinted, m4 bare. This
        // test fails under that alternative implementation, which is the
        // point — it pins which of the two the shipped code does.
        await _pump(tester, <TimelineBoardColumn>[
          TimelineBoardColumn(
            header: _entry('m1', 'Оля Коваль'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m2', 'Ніна Бойко', dayOff: true),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m3', 'Іра Ткач'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m4', 'Настя Гриб'),
            bookings: const <Booking>[],
          ),
        ]);

        final Color c2 = await _paintedColorAt(tester, 2);
        final Color c3 = await _paintedColorAt(tester, 3);

        expect(
          c2,
          BrandColors.base,
          reason: 'slot 2 is even by raw index — bare',
        );
        expect(
          c3,
          isNot(BrandColors.base),
          reason: 'slot 3 is odd by raw index — tinted',
        );
      },
    );
  });

  // Phase 342 gap — the band gained a perceptibility floor above but the
  // gutter divider (also re-tuned, 0.16 -> 0.24, in the very same fix) did
  // not, and is subject to the identical failure mode: an alpha regression
  // back toward the old value passes every exact-value check while reading
  // as invisible on a real screen. This group closes that gap, and also
  // pins the two properties the fix's doc comments CLAIM but nothing
  // previously asserted: that the band and the day-off wash move in
  // opposite directions off base (so they can never collapse into "one
  // effect, two strengths"), and that all three washes plus the divider
  // remain mutually distinguishable side by side — the way a user actually
  // scans the board, not one isolated swatch at a time.
  group('the divider and cross-wash distinguishability', () {
    testWidgets(
      'the column divider clears the same perceptibility floor as the band',
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

        expect(
          _minChannelDelta(_composited(divider.color), BrandColors.base),
          greaterThanOrEqualTo(kAlternatingBandMinDelta),
          reason:
              'the gutter divider must be perceptibly different from the '
              'base surface, not just technically unequal — it failed '
              'this exact check at the old alpha 0.16 before Phase 342 '
              'raised it to 0.24',
        );
      },
    );

    testWidgets(
      'the band LIFTS while a day-off column SINKS — divergent direction, '
      'not merely divergent strength',
      (WidgetTester tester) async {
        await _pump(tester, <TimelineBoardColumn>[
          TimelineBoardColumn(
            header: _entry('m1', 'Оля Коваль'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m2', 'Ніна Бойко'), // odd slot -> tinted
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m3', 'Іра Ткач', dayOff: true),
            bookings: const <Booking>[],
          ),
        ]);

        final Color band = await _paintedColorAt(tester, 1);
        final Color dayOff = _composited(
          tester
              .widget<ColoredBox>(
                find.byKey(
                  const ValueKey<String>('timeline-column-day-off-wash-2'),
                ),
              )
              .color,
        );
        const Color base = BrandColors.base;

        expect(
          _channel8(band.r),
          greaterThan(_channel8(base.r)),
          reason: 'the band must LIFT the red channel above base',
        );
        expect(
          _channel8(band.g),
          greaterThan(_channel8(base.g)),
          reason: 'the band must LIFT the green channel above base',
        );
        expect(
          _channel8(band.b),
          greaterThan(_channel8(base.b)),
          reason: 'the band must LIFT the blue channel above base',
        );

        expect(
          _channel8(dayOff.r),
          lessThan(_channel8(base.r)),
          reason: 'day-off must SINK the red channel below base',
        );
        expect(
          _channel8(dayOff.g),
          lessThan(_channel8(base.g)),
          reason: 'day-off must SINK the green channel below base',
        );
        expect(
          _channel8(dayOff.b),
          lessThan(_channel8(base.b)),
          reason: 'day-off must SINK the blue channel below base',
        );
      },
    );

    testWidgets(
      'band, day-off wash, and divider are all mutually distinguishable '
      'side by side — the way a user actually scans the board',
      (WidgetTester tester) async {
        // Columns: m1(work,0,bare) m2(work,1,tinted-odd) m3(OFF,2).
        await _pump(tester, <TimelineBoardColumn>[
          TimelineBoardColumn(
            header: _entry('m1', 'Оля Коваль'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m2', 'Ніна Бойко'),
            bookings: const <Booking>[],
          ),
          TimelineBoardColumn(
            header: _entry('m3', 'Іра Ткач', dayOff: true),
            bookings: const <Booking>[],
          ),
        ]);

        const Color base = BrandColors.base;
        final Color band = await _paintedColorAt(tester, 1);
        final Color dayOff = _composited(
          tester
              .widget<ColoredBox>(
                find.byKey(
                  const ValueKey<String>('timeline-column-day-off-wash-2'),
                ),
              )
              .color,
        );
        final Color divider1 = _composited(
          tester
              .widget<ColoredBox>(
                find.byKey(const ValueKey<String>('timeline-column-divider-1')),
              )
              .color,
        );

        // 'day-off vs divider' is deliberately NOT in this table. The
        // divider is painted in the 6dp gutter, centred at
        // `i * columnPitch - gutter / 2` — it never overlaps either wash's
        // `Positioned` rect (each wash starts exactly at a column boundary),
        // so on a real board the divider's background is always
        // [BrandColors.base], never a wash. Measured here: day-off
        // (shadowDarkCard@0.35) and the divider (accent@0.24) both sink off
        // base and land within min-channel delta 1 of EACH OTHER — a
        // coincidence of two independent design tokens, not a rendering
        // defect, since the two never share a pixel. Neither this file's
        // nor the production file's doc comments claim divider-vs-day-off
        // distinguishability; the divider's own doc only claims a seam
        // "next to the ... alternating band" (covered by 'band vs divider'
        // below). Asserting the undocumented, geometrically-unrealized pair
        // would pin a coincidence, not a user-visible property — see this
        // file's mutation log for the RED it produces and why it was
        // dropped rather than "fixed" by loosening the floor.
        final Map<String, int> pairs = <String, int>{
          'band vs base': _minChannelDelta(band, base),
          'day-off vs base': _minChannelDelta(dayOff, base),
          'divider vs base': _minChannelDelta(divider1, base),
          'band vs day-off': _minChannelDelta(band, dayOff),
          'band vs divider': _minChannelDelta(band, divider1),
        };

        for (final MapEntry<String, int> pair in pairs.entries) {
          expect(
            pair.value,
            greaterThanOrEqualTo(kAlternatingBandMinDelta),
            reason:
                '${pair.key} must clear the perceptibility floor so a '
                'user scanning the board tells the two apart',
          );
        }
      },
    );
  });
}
