// Phase 7.7 — the «Мої записи» date/period calendar.
// Phase 7.13 — retired the range/period behaviour: the filter sheet's Дата
// section is gone (a query the backend, and `BookingsDayQuery`, can no
// longer express — see `bookings_day_query.dart`'s header), and the rail's
// calendar escape hatch is now a SINGLE-DAY jump.
//
// ## This is a thin binding, not a second calendar
//
// `showBookingsDayPicker` opens `shared/widgets/period_range_picker.dart`'s
// `PeriodRangePicker` in `PeriodRangePickerMode.single` — the exact same
// scrolling month grid the schedule feature's period picker uses, just with a
// tap resolving immediately instead of requiring a start/end pair and a
// «Зберегти» confirm. Transcribing a second calendar for "pick one day"
// would have shipped a 600-line duplicate of a widget already in the tree;
// see `period_range_picker.dart`'s Phase 7.13 header section for why `mode`
// is additive rather than a fork.
//
// ## Why the jump survives at all (user decision, 2026-07-18)
//
// The rail spans ±180 days. This same chain fixed a bug where the picker
// opened roughly six months in the past, forcing manual scrolling to reach
// today. Retiring the jump entirely would reintroduce that class of problem
// for any day more than a few rail-scrolls out — so it survives, narrowed to
// exactly what the rail needs: pick ONE day, move the rail there.
//
// ## The three ways this still differs from the schedule caller
//
//   1. **The past is reachable.** The schedule picker applies a template to a
//      FUTURE period and gates out everything before today. Bookings live in
//      both directions — the whole point of the master's list is reviewing
//      what already happened — so the window opens at `today − 180 days`.
//   2. **Both ends are bounded.** ±180 days mirrors the day rail exactly (see
//      [kBookedDaysSpanDays]), so the calendar can never hand back a day the
//      rail cannot also show. A day the master picked but cannot find again is
//      worse than a day they cannot pick.
//   3. **It opens on the CURRENT SELECTION, not on the window's origin.**
//      [showBookingsDayPicker]'s `initialDay` seeds both the scroll target
//      AND the picker's initial highlighted day — opening on
//      `today − 180 days` would repeat the exact six-months-of-scrolling bug
//      this jump exists to prevent, just relocated from "today" to "wherever
//      the rail currently is".
//
// There is no span cap here (Phase 7.13 retired `kMaxBookingRangeDays` along
// with it) — a single day trivially satisfies any width limit the backend
// could ever impose on a range it will never receive from this control.
//
// ## Dates stay host-local, deliberately
//
// Every bound here is a date-only `DateTime` in the DEVICE's zone, derived by
// CALENDAR arithmetic (`DateTime(y, m, d + n)`, never `Duration(days: n)` —
// see `bookings_day_rail.dart`'s header for the DST skew that causes). The
// resolved day is normalised through [dateOnly] before being handed back —
// belt-and-braces, since `BookingsDayQuery.of()` truncates again on the way
// in, but a picker that returns a TIMESTAMPED `DateTime` is exactly how the
// family leak `scripts/forbid_raw_bookings_query.sh` polices gets
// reintroduced one refactor later.
//
// There IS a known tension here: the rail and this picker are host-local
// while booking TIMES are pinned to Europe/Kyiv via `toBeauticaTime`, so a
// master travelling outside Kyiv can see a booking whose displayed time sits
// on a different calendar day than the filter bucket it lands in. That is an
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

/// Opens the «Мої записи» single-day jump calendar, resolving with the
/// chosen date-only day, or `null` when dismissed without picking.
///
/// [today] is the screen's captured date-only Kyiv "today" — passed in
/// rather than read from the clock so the picker's window is anchored to
/// exactly the same day the rail was built around, even across a midnight
/// rollover mid-session. [initialDay] is the CURRENTLY SELECTED day — the
/// picker opens scrolled to (and highlighting) it, not to the window's
/// six-months-back origin. See the file header for why that distinction is
/// load-bearing.
Future<DateTime?> showBookingsDayPicker(
  BuildContext context, {
  required DateTime today,
  required DateTime initialDay,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);

  // CALENDAR arithmetic on both bounds — `railDayAt`, the same function the
  // rail derives its own cells with.
  final DateTime firstDay = railDayAt(today, -kBookedDaysSpanDays);
  final DateTime lastDay = railDayAt(today, kBookedDaysSpanDays);
  final DateTime day = dateOnly(initialDay);

  final DateTimeRange? picked = await showPeriodRangePicker(
    context,
    firstMonth: DateTime(firstDay.year, firstDay.month),
    firstSelectableDay: firstDay,
    lastSelectableDay: lastDay,
    // Scroll to (and pre-highlight, via `initialRange`) the CURRENT
    // selection, not `firstMonth` — see the file header's point 3. Without
    // this the calendar opens six months behind wherever the rail actually
    // is, which is the exact bug this jump exists to prevent.
    initialScrollMonth: DateTime(day.year, day.month),
    initialRange: DateTimeRange(start: day, end: day),
    // The window spans ~12 months either side of today, so it can straddle up
    // to 13 calendar months; 14 renders the whole reachable range with a month
    // of slack at each edge and never leaves a selectable day off the list.
    monthCount: 14,
    mode: PeriodRangePickerMode.single,
    strings: PeriodRangePickerStrings(
      title: l10n.bookingDayPickerTitle,
      emptyHint: l10n.bookingDayPickerEmptyHint,
      backSemantic: l10n.bookingDayPickerBack,
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
  if (picked == null) return null;
  // Belt-and-braces date-only normalisation — see the file header.
  return dateOnly(picked.start);
}
