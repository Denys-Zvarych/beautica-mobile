// Phase 14.1 — booking-flow date/time label composition (Europe/Kyiv-aware).
//
// The Ukrainian calendar vocabulary (month/weekday names) used to be five
// fixed consts defined in this file. Phase 23.3 deleted them and repointed
// every lookup at `shared/formatters/uk_calendar.dart`, the single canonical
// home for that vocabulary across the app (see that file's header for the
// "why hand-authored, not `AppLocalizations`/`intl`" rationale — this app is
// UA-primary; l10n infrastructure is reserved for genuinely translatable UI
// copy, a decision upheld unchanged since Phase 23.1). This file now owns two
// things only: composing the resolved words into the booking flow's specific
// label shapes, and converting each incoming instant to the salon wall-clock
// before any word or field is read from it.
//
// TIMEZONE: every incoming instant is canonical UTC (the generated built_value
// client normalises every wire `DateTime` to UTC). Every formatter below
// converts it to the salon market wall-clock (Europe/Kyiv, DST-aware) via
// [toBeauticaTime] before reading any hour/minute/day/weekday/month field —
// NOT device `.toLocal()`, which rendered wrong on non-Kyiv devices and failed
// on CI's UTC runner. The stored/transmitted instant is never mutated; this is
// display-only. `initBeauticaTimeZones()` must have run (app startup / test
// harness) before these are called.
//
// Pure Dart — no Flutter imports.

import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

String _twoDigits(int v) => v.toString().padLeft(2, '0');

/// Formats [day] as a compact day-header chip label, e.g. "пн, 14 лип".
///
/// The incoming instant is canonical UTC (the generated built_value client
/// normalises every wire `DateTime` to UTC); it is converted to the Europe/Kyiv
/// wall-clock via [toBeauticaTime] so the DATE reads at the salon's local zone —
/// a late-evening Kyiv slot is a previous-day date in UTC, so the
/// day/weekday/month must all come from the Kyiv value.
String formatBookingDayHeader(DateTime day) {
  final DateTime local = toBeauticaTime(day);
  final String wd = weekdayAbbrev(local.weekday);
  final String mon = monthAbbrev(local.month);
  return '$wd, ${local.day} $mon';
}

/// Formats the chosen appointment window, e.g. "вт, 14 лип · 14:00–18:30".
///
/// Both instants are converted to the Europe/Kyiv wall-clock first (see
/// [formatBookingDayHeader]) so the date and both times read at the salon's
/// local zone rather than the raw UTC hour.
String formatBookingWindow(DateTime start, DateTime end) {
  final DateTime startLocal = toBeauticaTime(start);
  final DateTime endLocal = toBeauticaTime(end);
  final String wd = weekdayAbbrev(startLocal.weekday);
  final String mon = monthAbbrev(startLocal.month);
  final String s =
      '${_twoDigits(startLocal.hour)}:${_twoDigits(startLocal.minute)}';
  final String e =
      '${_twoDigits(endLocal.hour)}:${_twoDigits(endLocal.minute)}';
  return '$wd, ${startLocal.day} $mon · $s–$e';
}

/// Formats a bare time-of-day as "HH:mm".
///
/// Converts the canonical-UTC instant to the Europe/Kyiv wall-clock first so the
/// picker prints the Kyiv time (09:00), not the raw UTC hour (06:00).
String formatSlotTime(DateTime time) {
  final DateTime local = toBeauticaTime(time);
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

/// The chosen day spelled out in full, e.g. "понеділок, 14 липня" — full
/// weekday + day + genitive full month. Used by the booking confirm/success
/// summary cards' full-width "Дата" row so it is never abbreviated or clipped
/// (unlike [formatBookingDayHeader]'s compact chip form).
String formatFullDate(DateTime day) {
  final DateTime local = toBeauticaTime(day);
  final String wd = weekdayName(local.weekday);
  final String mon = monthGenitive(local.month);
  return '$wd, ${local.day} $mon';
}

/// The booked time range only (no date): [start] → `start +` [totalMinutes],
/// e.g. "14:00–18:30". Used by the booking confirm/success summary cards'
/// "Час" row, paired with [formatFullDate] on its own "Дата" row.
String formatTimeRange(DateTime start, int totalMinutes) {
  // Convert to the Europe/Kyiv wall-clock BEFORE adding the duration so both
  // ends read at the salon's local zone (see [formatSlotTime]). `.add` on a
  // TZDateTime stays in the same location and correctly spans a DST boundary.
  final DateTime startLocal = toBeauticaTime(start);
  final DateTime endLocal = startLocal.add(Duration(minutes: totalMinutes));
  return '${_twoDigits(startLocal.hour)}:${_twoDigits(startLocal.minute)}'
      '–${_twoDigits(endLocal.hour)}:${_twoDigits(endLocal.minute)}';
}

/// The booked time range from TWO REAL INSTANTS, e.g. "14:00–18:30" — the
/// master's «Мої записи» timeline card (`master_booking_card.dart`, both its
/// compact and full layouts).
///
/// ## Why this exists alongside [formatTimeRange]
///
/// [formatTimeRange] derives its end from `start + totalMinutes`, because its
/// callers (the booking confirm/success summary cards, «Деталі запису», the
/// salon appointment card) are describing an appointment being ASSEMBLED from
/// a service duration — there is no server-side end instant to read yet, only
/// a start and a duration to add.
///
/// A persisted `Booking` is the other case: it carries a real `endAt` from the
/// backend alongside its `startAt`. Re-deriving the end from
/// `durationMinutes` there would introduce a second, independently-driftable
/// answer to "when does this finish" — so a card holding a genuine `endAt`
/// must format THAT, which is what this function takes. Deliberately two
/// functions rather than one with an optional `end`: the choice is a real
/// semantic fork (derived vs. persisted end), and an optional parameter would
/// let a `Booking` call site silently fall back to the derived branch.
///
/// Both instants are converted to the Europe/Kyiv wall-clock via
/// [toBeauticaTime] BEFORE any hour/minute is read (see [formatSlotTime]) —
/// the wire values are canonical UTC, so a late-evening Kyiv appointment would
/// otherwise print the wrong hour on both ends. Same en-dash separator as
/// [formatTimeRange] and [formatBookingWindow].
String formatSlotTimeRange(DateTime start, DateTime end) {
  final DateTime startLocal = toBeauticaTime(start);
  final DateTime endLocal = toBeauticaTime(end);
  return '${_twoDigits(startLocal.hour)}:${_twoDigits(startLocal.minute)}'
      '–${_twoDigits(endLocal.hour)}:${_twoDigits(endLocal.minute)}';
}

// Phase 14.3 — My Bookings card date stub.

/// The booking card's date-stub second line: genitive month + short weekday,
/// e.g. "червня, ср". Sits under the big day number, so the day itself is NOT
/// repeated here — the two lines read as one date:
///
/// ```
/// 18
/// червня, ср
/// ```
///
/// The weekday is the short form because on the stub it is a qualifier, not
/// the subject — the client is scanning for a number, then checking which day
/// of the week it lands on.
///
/// (A sibling `formatShortDateTime` — "12 лип, 14:30" — lived here until the
/// master timeline card dropped its per-card date in favour of a bare
/// [formatSlotTimeRange]; it was deleted rather than left as an unused
/// formatter, since its only caller was that card.)
String formatStubDayLine(DateTime day) {
  final DateTime local = toBeauticaTime(day);
  final String mon = monthGenitive(local.month);
  final String wd = weekdayAbbrev(local.weekday);
  return '$mon, $wd';
}
