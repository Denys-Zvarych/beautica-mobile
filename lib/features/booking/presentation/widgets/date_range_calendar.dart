// Phase 7.7 — the «Мої записи» date/period calendar.
//
// ## This is a thin binding, not a second calendar
//
// The design's `DateRangeCalendar.show(...)`
// (`docs/signup-designs/SalonManagementDesign/lib/widgets/
// date_range_calendar.dart`) is the SAME widget as the schedule feature's
// `PeriodRangePicker`, which is already its production port — the preview file
// even says so in its own header ("Ported from the independent-master
// schedule's `PeriodRangePicker`"). Transcribing it again would have shipped a
// 600-line duplicate of a widget already in the tree.
//
// So Phase 7.7 promoted `PeriodRangePicker` from `features/schedule/
// presentation/` to `shared/widgets/` (a cross-feature import may only go
// through `domain/` or `shared/`) and gave it the three parameters the booking
// filter needs. This file is what remains: resolving the copy and the four
// bounds, and nothing else.
//
// ## The three ways this differs from the schedule caller
//
//   1. **The past is reachable.** The schedule picker applies a template to a
//      FUTURE period and gates out everything before today. Bookings live in
//      both directions — the whole point of the master's list is reviewing
//      what already happened — so the window opens at `today − 180 days`.
//   2. **Both ends are bounded.** ±180 days mirrors the day rail exactly (see
//      [kBookedDaysSpanDays]), so the calendar can never hand back a day the
//      rail cannot also show. A day the master picked but cannot find again is
//      worse than a day they cannot pick.
//   3. **The span is capped.** [kMaxBookingRangeDays] days, enforced by
//      DISABLING out-of-reach days once a start is chosen — not by reporting a
//      violation after the fact. Backend 26.2 answers a wider window with a
//      400, and the user should never be able to build one.
//
// ## Dates stay host-local, deliberately
//
// Every bound here is a date-only `DateTime` in the DEVICE's zone, derived by
// CALENDAR arithmetic (`DateTime(y, m, d + n)`, never `Duration(days: n)` —
// see `bookings_day_rail.dart`'s header for the DST skew that causes) and
// serialised by `toApiDate`, which reads `.year`/`.month`/`.day` off the local
// value with no zone conversion at all.
//
// There IS a known tension here: the rail and this picker are host-local while
// booking TIMES are pinned to Europe/Kyiv via `toBeauticaTime`, so a master
// travelling outside Kyiv can see a booking whose displayed time sits on a
// different calendar day than the filter bucket it lands in. That is an
// architecture decision, currently backlogged, and it is NOT resolved here.
// What matters for this phase is that the picker and the rail share one day
// basis, so the two always agree with each other; changing only one of them
// would turn a coherent skew into an incoherent one.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/month_names.dart';
import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';

import '../../application/booked_days_notifier.dart';
import 'bookings_day_rail.dart';

/// Widest `from`/`to` window `GET /bookings/me` accepts (backend Phase 26.2);
/// anything wider is a 400.
///
/// The rail's own span is `2 * kBookedDaysSpanDays + 1` = 361 days, chosen to
/// sit deliberately UNDER this cap. Do not widen the rail to close the gap.
const int kMaxBookingRangeDays = 366;

/// Opens the «Мої записи» date/period calendar, resolving with the chosen
/// inclusive local-date bounds (a single day is `start == end`), or `null` when
/// dismissed.
///
/// [today] is the screen's captured date-only "today" — passed in rather than
/// read from the clock so the picker's window is anchored to exactly the same
/// day the rail was built around, even across a midnight rollover mid-session.
Future<DateTimeRange?> showBookingsDateRangePicker(
  BuildContext context, {
  required DateTime today,
  DateTimeRange? initialRange,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);

  // CALENDAR arithmetic on both bounds — `railDayAt`, the same function the
  // rail derives its own cells with.
  final DateTime firstDay = railDayAt(today, -kBookedDaysSpanDays);
  final DateTime lastDay = railDayAt(today, kBookedDaysSpanDays);

  return showPeriodRangePicker(
    context,
    firstMonth: DateTime(firstDay.year, firstDay.month),
    firstSelectableDay: firstDay,
    lastSelectableDay: lastDay,
    // Open on TODAY's month, not on `firstMonth`.
    //
    // `firstMonth` is six months back (see point 1 above), and the picker
    // scrolls to it when there is no `initialRange` — so the calendar opened
    // roughly six months in the past and the master had to scroll a quarter of
    // a year to reach today before they could pick anything. Same bug class the
    // day rail had at its own `today − 180` origin, fixed there in Phase 7.6.
    //
    // An `initialRange` still wins: reopening the picker with a window already
    // set scrolls to that window, which is the more specific intent.
    initialScrollMonth: DateTime(today.year, today.month),
    maxSpanDays: kMaxBookingRangeDays,
    // The window spans ~12 months either side of today, so it can straddle up
    // to 13 calendar months; 14 renders the whole reachable range with a month
    // of slack at each edge and never leaves a selectable day off the list.
    monthCount: 14,
    initialRange: initialRange,
    strings: PeriodRangePickerStrings(
      title: l10n.bookingFilterDatePickerTitle,
      emptyHint: l10n.bookingFilterDatePickerEmptyHint,
      saveLabel: l10n.bookingFilterDatePickerSave,
      backSemantic: l10n.bookingFilterDatePickerBack,
      weekdayShort: <String>[
        l10n.weekdayShortMon,
        l10n.weekdayShortTue,
        l10n.weekdayShortWed,
        l10n.weekdayShortThu,
        l10n.weekdayShortFri,
        l10n.weekdayShortSat,
        l10n.weekdayShortSun,
      ],
      monthNames: monthNamesNominative,
    ),
  );
}

/// Normalises a picked [range] to the date-only bounds the query wants.
///
/// The picker already works in date-only values, so this is belt-and-braces —
/// but `MasterBookingsQuery.of` normalises again on the way in, and doing it
/// here too keeps the pair handed to the screen directly comparable to the
/// rail's days without depending on which of the two ran first.
({DateTime from, DateTime to}) normaliseBookingRange(DateTimeRange range) {
  final DateTime a = dateOnly(range.start);
  final DateTime b = dateOnly(range.end);
  return a.isAfter(b) ? (from: b, to: a) : (from: a, to: b);
}
