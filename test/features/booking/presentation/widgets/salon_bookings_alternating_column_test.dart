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
}
