// Chrome golden — the salon «Записи» board's COLUMN BACKGROUND
// (`_BoardStack` inside
// `lib/features/booking/presentation/widgets/bookings_timeline_grid.dart`).
//
// WHY THIS FILE EXISTS
// --------------------
// `grep -rn "BookingsTimelineGrid" test/golden/` returned nothing before this
// file: the board — the densest, most colour-sensitive surface in the app —
// had no pixel baseline at all. Its own source said so out loud ("NO GOLDENS
// ON THIS WIDGET"), and that gap is exactly how a near-white column wash
// (`BrandColors.shadowLightStrong` @ 0.55, compositing to `#F4EEE4`) shipped
// twice in a row: first invisible, then glaring. Both passes were reviewed as
// NUMBERS in a diff. Neither was ever reviewed as an IMAGE.
//
// From here a colour pass on this board produces a PNG diff a human looks at.
//
// THE TWO CELLS, AND WHY THEY ARE THE PAIR THEY ARE
// -------------------------------------------------
// Both cells render the same two-master board at the same 360dp geometry
// (148dp column, 6dp gutter). They differ in ONE thing — column 1's state —
// so any pixel difference beyond that column is a regression:
//
//  1. OCCUPIED + DAY OFF   — column 0 works and carries two bookings;
//     column 1 is «Вихідний». Column 1 is the documented column STATE, and
//     it must read as a SINK (`shadowDarkCard@0.35`).
//  2. OCCUPIED + WORKING-EMPTY — column 0 identical; column 1 works and has
//     nothing booked. Column 1 must be INDISTINGUISHABLE from the base tone
//     that runs behind column 0: a master column has no background of its
//     own, per the approved preview
//     (`docs/signup-designs/SalonBookingsBoard/lib/widgets/
//     bookings_timeline_board.dart`, `_GridStack.build`).
//
// Cell 2's column 1 is deliberately at ODD index and WORKING — the exact
// conjunction the removed `_AlternatingColumnBandPainter` gated on. A cell
// pairing an occupied column with a DAY-OFF column alone would have been
// blind to the defect, because the band skipped day-off columns; that is why
// there are two cells and not one.
//
// A NOTE ON WHAT THIS BASELINE IS NOT
// -----------------------------------
// A golden regenerated from the code under test is self-referential and is
// NOT acceptance for the colour bug it was born from. The CORRECTNESS of the
// column background — that every non-day-off column body rasterizes to
// exactly `BrandColors.base`, on every column index, and that nothing on the
// board lifts above it — is established independently, and by direct pixel
// measurement rather than by comparison against these bytes, in
// `test/features/booking/presentation/widgets/
// salon_bookings_board_pixel_census_test.dart`. This PNG's job from here is
// unintended pixel DRIFT.
//
// These baselines were generated against the FIXED tree and then MUTATION-
// PROVED: reinstating the band turns cell 2 red. See the QA report.
//
// MATRIX: {360} dp × {1.0} scale — the convention
// `master_column_strip_golden_test.dart` established for this board's chrome.
// Suite config renders CI-mode goldens (`obscureText: true`,
// `renderShadows: false`), so text is coloured blocks and the card's ambient
// blur is suppressed; the column FILLS this file exists for are neither, and
// render normally.
//
// CLOCK: the grid reads no clock — it renders no "now" marker and no
// date-derived state; `day` is a plain fixture argument. Nothing here drifts
// with the host clock or its timezone.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const String _kDayOffFile = 'salon_bookings_board_day_off_360_1x';
const String _kWorkingEmptyFile = 'salon_bookings_board_working_empty_360_1x';

/// The 360dp Android baseline — `TimelineDensity.salon` resolves to a 148dp
/// column and a 6dp gutter here, and TWO masters fill the lane viewport
/// exactly, so nothing scrolls and no `StripScrollIndicator` floats over the
/// board.
const double _kWidth = 360;

/// Strip + board at `firstHour = 10`, `lastHour = 12`, with slack.
const double _kCellHeight = 300;

/// future-date-ok: a fixed PAST Kyiv day. The grid reads no clock, so this is
/// inert fixture data — it exists only because `day:` is required.
final DateTime _day = DateTime(2026, 6, 15);

/// future-date-ok: the same fixed PAST day as the canonical UTC instant.
final DateTime _dayUtcMidnight = DateTime.utc(2026, 6, 15);

/// Kyiv is UTC+3 in June.
DateTime _kyiv(int hour, int minute) =>
    _dayUtcMidnight.add(Duration(hours: hour - 3, minutes: minute));

/// i18n-finder-ok / raw strings: golden fixture data feeding the board's
/// opaque slots, not production UI copy governed by l10n.
Booking _booking({
  required String id,
  required int hour,
  required int minute,
  required int durationMinutes,
}) {
  final DateTime start = _kyiv(hour, minute);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    serviceName: 'Манікюр',
    durationMinutes: durationMinutes,
    price: 500,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
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

/// Column 0 in BOTH cells — identical, so the pair diffs down to column 1.
/// Two bookings with a real gap between them: the wash showed BETWEEN and
/// BELOW cards, so the image has to contain both kinds of background.
List<Booking> _occupied() => <Booking>[
  _booking(id: 'g1', hour: 10, minute: 0, durationMinutes: 60),
  _booking(id: 'g2', hour: 11, minute: 30, durationMinutes: 30),
];

Widget _board({required bool dayOff}) => ColoredBox(
  // The production ground — `app_theme.dart:24`'s `scaffoldBackgroundColor`,
  // which the grid itself never paints.
  color: BrandColors.base,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: BookingsTimelineGrid(
      bookings: _occupied(),
      day: _day,
      onBookingTap: _noop,
      density: TimelineDensity.salon,
      columns: <TimelineBoardColumn>[
        TimelineBoardColumn(
          header: _entry('m1', 'Оля Коваль'),
          bookings: _occupied(),
        ),
        TimelineBoardColumn(
          header: _entry('m2', 'Ніна Бойко', dayOff: dayOff),
          bookings: const <Booking>[],
        ),
      ],
    ),
  ),
);

void _noop(Booking _) {}

Widget _host({required bool dayOff}) => SizedBox(
  height: _kCellHeight,
  child: _board(dayOff: dayOff),
);

void main() {
  // Cell 1 — column 1 is «Вихідний»: the one documented column state, and the
  // only column on this board that may differ from the base tone.
  goldenTest(
    'salon bookings board — occupied column beside a DAY-OFF column',
    fileName: _kDayOffFile,
    constraints: BoxConstraints.tight(const Size(_kWidth, _kCellHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: _kWidth),
    builder: () => _host(dayOff: true),
  );

  // Cell 2 — column 1 works and is empty. ODD index + WORKING is exactly what
  // the removed alternating band gated on, so this is the cell a
  // reintroduced wash turns red.
  goldenTest(
    'salon bookings board — occupied column beside a WORKING, EMPTY column '
    '(odd index: the removed band\'s exact target)',
    fileName: _kWorkingEmptyFile,
    constraints: BoxConstraints.tight(const Size(_kWidth, _kCellHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: _kWidth),
    builder: () => _host(dayOff: false),
  );
}
