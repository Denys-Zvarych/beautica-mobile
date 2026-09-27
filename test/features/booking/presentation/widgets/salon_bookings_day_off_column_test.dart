// Phase 336 — what a NOT-WORKING master's column actually LOOKS like on the
// salon «Записи» board.
//
// The predicate ("is this master off?") is pinned next door, as a pure
// function, in `test/features/salon/presentation/salon_bookings_day_off_test
// .dart`. This file pins the RENDER of its `true` answer, which is the half
// the user reported:
//
//   > "if any master have day off in that day - u can show that master column
//      as gray and with title day off etc."
//
// so there are exactly two claims, and both are MEASURED on screen rather
// than read off a widget field:
//
//   1. THE TITLE. The column says «Вихідний», not «Вільний день». A board
//      where one column is off and another is merely empty must render TWO
//      different strings — asserted together, in one tree, because the bug
//      was precisely that they were one string.
//   2. THE GREY. A wash band exists over the off column, is exactly that
//      column's width, starts exactly at that column's left edge, and does
//      NOT exist anywhere on a board with nobody off. Rect-compared against
//      the roster chip above it, which is the same alignment contract the
//      board's single shared `ScrollPosition` already guarantees.
//
// Plus the roster chip's own readout, which is the second surface the mark
// reaches.
//
// CLOCK / TZ: one fixed PAST Kyiv date, geometry-only assertions, no
// real-clock predicate read anywhere. `TZ=UTC` changes no expectation.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
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

MasterColumnEntry _entry(
  String id,
  String name,
  int count, {
  bool dayOff = false,
}) => MasterColumnEntry(
  masterId: id,
  name: name,
  type: MasterType.salonMaster,
  bookingCount: count,
  professionalTitle: 'Стиліст',
  avgRating: 4.8,
  dayOff: dayOff,
);

/// The UA strings under test, pulled from the generated delegate rather than
/// typed as literals — `forbid_cyrillic_finder.sh` forbids the literals, and
/// rightly: a `find.text('Вихідний')` silently becomes `findsNothing` the day
/// EN ships, which would retire this whole file without anyone noticing.
final AppLocalizationsUk _uk = AppLocalizationsUk();

Rect _chipRect(WidgetTester tester, String masterId) => tester.getRect(
  find.byKey(ValueKey<String>('salon-bookings-column-chip-$masterId')),
);

Rect _washRect(WidgetTester tester, int index) => tester.getRect(
  find.byKey(ValueKey<String>('timeline-column-day-off-wash-$index')),
);

Future<void> _pump(
  WidgetTester tester,
  List<TimelineBoardColumn> columns,
) async {
  await tester.pumpApp(
    Padding(
      // `_kBoardBodyPadding` — the real inset the salon scope uses, so the
      // lane viewport under test is the one the screen produces.
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

void main() {
  // The board under test: m1 works and is booked, m2 works and is EMPTY, m3
  // is OFF. m2 and m3 are the pair the bug conflated.
  List<TimelineBoardColumn> mixedBoard() => <TimelineBoardColumn>[
    TimelineBoardColumn(
      header: _entry('m1', 'Оля Коваль', 1),
      bookings: <Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)],
    ),
    TimelineBoardColumn(
      header: _entry('m2', 'Ніна Бойко', 0),
      bookings: const <Booking>[],
    ),
    TimelineBoardColumn(
      header: _entry('m3', 'Іра Ткач', 0, dayOff: true),
      bookings: const <Booking>[],
    ),
  ];

  group('the day-off column STATES that it is a day off', () {
    testWidgets(
      'an empty OFF column and an empty WORKING column render DIFFERENT '
      'markers in the same tree',
      (WidgetTester tester) async {
        await _pump(tester, mixedBoard());

        // Column 1 (m2) — working, nothing booked.
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('timeline-column-marker-1')),
              )
              .data,
          _uk.salonBookingsColumnFreeDay,
        );
        // Column 2 (m3) — not working at all.
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('timeline-column-marker-2')),
              )
              .data,
          _uk.salonBookingsColumnDayOff,
        );
        // …and they are genuinely two different strings, so the assertions
        // above cannot both pass on one shared value.
        expect(
          _uk.salonBookingsColumnDayOff,
          isNot(_uk.salonBookingsColumnFreeDay),
        );
      },
    );

    testWidgets('an OFF column that still carries a booking keeps its cards', (
      WidgetTester tester,
    ) async {
      // A walk-in placed onto a master's day off. The salon board never drops
      // a booking, so the mark must never replace the cards — the wash and
      // the chip carry the state instead.
      await _pump(tester, <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль', 1, dayOff: true),
          bookings: <Booking>[_booking(id: 'walkin', masterId: 'm1', hour: 10)],
        ),
      ]);
      expect(
        find.byKey(const ValueKey<String>('timeline-card-walkin')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-column-marker-0')),
        findsNothing,
        reason: 'no banner floated over live cards',
      );
      // …but it is still greyed.
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-0')),
        findsOneWidget,
      );
    });
  });

  group('the grey wash', () {
    testWidgets('covers EXACTLY the off column, and only it', (
      WidgetTester tester,
    ) async {
      await _pump(tester, mixedBoard());

      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-column-day-off-wash-1')),
        findsNothing,
      );

      // MEASURED against the chip pinned above the same column — the board's
      // one shared horizontal `ScrollPosition` is what makes those two
      // coordinates comparable, so a wash that drifted off its column fails
      // here even though its own `SizedBox(width:)` would still read right.
      final Rect wash = _washRect(tester, 2);
      final Rect chip = _chipRect(tester, 'm3');
      expect(wash.left, closeTo(chip.left, 0.5));
      expect(wash.width, closeTo(chip.width, 0.5));
      expect(
        wash.width,
        closeTo(148, 0.5),
        reason: 'the salon column width at the 360dp baseline',
      );
    });

    testWidgets('is absent entirely on a board with nobody off', (
      WidgetTester tester,
    ) async {
      // The back-compat claim: `dayOff` defaults to `false`, so a board built
      // the way every pre-existing caller builds one paints no wash at all.
      await _pump(tester, <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль', 1),
          bookings: <Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)],
        ),
        TimelineBoardColumn(
          header: _entry('m2', 'Ніна Бойко', 0),
          bookings: const <Booking>[],
        ),
      ]);
      for (int i = 0; i < 2; i++) {
        expect(
          find.byKey(ValueKey<String>('timeline-column-day-off-wash-$i')),
          findsNothing,
        );
      }
      expect(find.text(_uk.salonBookingsColumnDayOff), findsNothing);
    });

    testWidgets('paints UNDER the hour gridlines and under the cards', (
      WidgetTester tester,
    ) async {
      // A greyed column must stay a readable timeline. Asserted as paint
      // ORDER inside the `Stack`: the wash is emitted before the gridlines,
      // so it appears earlier among the `Stack`'s children.
      //
      // TWO HOPS SINCE 2026-09-20, not one. The banding children (day-off
      // washes, gridlines, gutter dividers) now live inside a
      // `Positioned.fill(RepaintBoundary(Stack(...)))` so a sibling repaint
      // cannot drag ~42 render objects with it (mobile-perf MEDIUM). The
      // invariant this test asserts is UNCHANGED and is now expressed in two
      // parts, both of which have to hold for "under the gridlines and under
      // the cards" to be true:
      //
      //   1. the whole banding layer is the FIRST child of the board `Stack`,
      //      so it paints under the column boxes (and therefore under every
      //      card);
      //   2. the wash is the FIRST child WITHIN that layer, so it paints under
      //      the gridlines and dividers that share it.
      //
      // Asserting only (2) would go green with the layer moved on top of the
      // cards; asserting only (1) would go green with the wash moved over the
      // gridlines. Both are required.
      await _pump(tester, <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль', 1, dayOff: true),
          bookings: <Booking>[_booking(id: 'a1', masterId: 'm1', hour: 10)],
        ),
      ]);
      // `timeline-column-stack` keys the `_BoardStack` WIDGET, not the
      // `Stack` it builds — hence the descendant hop. `.first` is the
      // outermost `Stack` in depth-first order, i.e. the board's own.
      final Finder stack = find
          .descendant(
            of: find.byKey(const ValueKey<String>('timeline-column-stack')),
            matching: find.byType(Stack),
          )
          .first;
      final List<Widget> children = tester.widget<Stack>(stack).children;

      // (1) The banding layer is the board `Stack`'s first child.
      final Widget first = children.first;
      expect(
        first,
        isA<Positioned>(),
        reason: 'the banding layer is a Positioned.fill',
      );
      final Widget boundary = (first as Positioned).child;
      expect(
        boundary,
        isA<RepaintBoundary>(),
        reason:
            'the banding layer must keep its own retained layer — without the '
            'boundary a sibling repaint drags every gridline with it',
      );

      // (2) The wash is that layer's own first child.
      final Widget bandingStack = (boundary as RepaintBoundary).child!;
      expect(bandingStack, isA<Stack>());
      final int washIndex = (bandingStack as Stack).children.indexWhere(
        (Widget w) =>
            w is Positioned &&
            w.child.key ==
                const ValueKey<String>('timeline-column-day-off-wash-0'),
      );
      expect(washIndex, 0, reason: 'the wash is the FIRST thing painted');
    });
  });

  group('the roster chip', () {
    testWidgets('draws NO load readout — the words moved to the column '
        'marker and to speech, the chip keeps only the identity', (
      WidgetTester tester,
    ) async {
      await _pump(tester, mixedBoard());
      // m1 is booked (1), m2 is working-and-free, m3 is off. None of the
      // three readout spellings the chip used to draw survives on it.
      expect(find.text(_uk.salonBookingsMasterColumnFree), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text(_uk.masterBookingsCount(1)), findsNothing);
      // «Вихідний» now appears EXACTLY ONCE — the grid's column marker under
      // the chip, which this phase deliberately leaves alone. Two would mean
      // the chip still draws it; zero would mean the marker regressed too.
      expect(find.text(_uk.salonBookingsColumnDayOff), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MasterColumnStrip),
          matching: find.text(_uk.salonBookingsColumnDayOff),
        ),
        findsNothing,
        reason: 'the surviving «Вихідний» is the GRID marker, not the chip',
      );

      // NOT VACUOUS: the chips are all still there, rendering the master
      // identity they exist for.
      for (final String name in <String>[
        'Оля Коваль',
        'Ніна Бойко',
        'Іра Ткач',
      ]) {
        expect(
          find.descendant(
            of: find.byType(MasterColumnStrip),
            matching: find.text(name),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('exposes the off state to a screen reader', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, mixedBoard());
      expect(
        // A RegExp, not the bare string: the chip's `Semantics` node MERGES
        // its descendants, so the node's own label is this phrase plus
        // whatever the merged children contribute, and
        // `bySemanticsLabel(String)` compares for EQUALITY.
        find.bySemanticsLabel(
          RegExp(
            RegExp.escape(
              _uk.salonBookingsMasterColumnSemantics(
                'Іра Ткач',
                'Стиліст',
                _uk.salonBookingsColumnDayOff,
              ),
            ),
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
