// Phase 14.1 — Ukrainian calendar vocabulary for the booking slot picker.
//
// Fixed calendar constants (month/weekday short forms), not translated user
// copy — mirrors the existing `duration_minutes.dart` / `service_price_display.dart`
// precedent of embedding Ukrainian words directly in a pure-Dart formatter
// rather than routing through `AppLocalizations` (this app is UA-primary;
// l10n infrastructure is reserved for genuinely translatable UI copy).
//
// Pure Dart — no Flutter imports.

/// Ukrainian month names in the nominative (calendar-header) form, January-first.
const List<String> kMonthsUk = <String>[
  'Січень',
  'Лютий',
  'Березень',
  'Квітень',
  'Травень',
  'Червень',
  'Липень',
  'Серпень',
  'Вересень',
  'Жовтень',
  'Листопад',
  'Грудень',
];

/// Short Ukrainian month forms used inside the chosen-window line ("14 лип").
const List<String> kMonthsUkShort = <String>[
  'січ',
  'лют',
  'бер',
  'кві',
  'тра',
  'чер',
  'лип',
  'сер',
  'вер',
  'жов',
  'лис',
  'гру',
];

/// Short Ukrainian weekday forms, Monday-first (index 0 = Monday, matching
/// [DateTime.weekday]'s 1-based Monday-first numbering via `weekday - 1`).
const List<String> kWeekdaysUkShort = <String>[
  'пн',
  'вт',
  'ср',
  'чт',
  'пт',
  'сб',
  'нд',
];

// Phase 14.2 — full weekday/genitive-month forms for the booking confirm +
// success summary cards' full-width "Дата" row (e.g. "понеділок, 14 липня"),
// which never abbreviates. Mirrors
// `docs/signup-designs/BookingConfirmSuccess/lib/util/uk_format.dart`
// verbatim (`kWeekdaysUkFull` / `kMonthsUkGenitive`), added to this existing
// file rather than a new `uk_format.dart` since the vocabulary belongs with
// the rest of the booking flow's calendar constants.

/// Full Ukrainian month forms in the genitive case, as they read after a day
/// number ("14 липня"). Used by [formatFullDate].
const List<String> kMonthsUkGenitive = <String>[
  'січня',
  'лютого',
  'березня',
  'квітня',
  'травня',
  'червня',
  'липня',
  'серпня',
  'вересня',
  'жовтня',
  'листопада',
  'грудня',
];

/// Full Ukrainian weekday names, Monday-first ("понеділок"…"неділя"). Used by
/// [formatFullDate].
const List<String> kWeekdaysUkFull = <String>[
  'понеділок',
  'вівторок',
  'середа',
  'четвер',
  'пʼятниця',
  'субота',
  'неділя',
];

String _twoDigits(int v) => v.toString().padLeft(2, '0');

/// Formats [day] as a compact day-header chip label, e.g. "пн, 14 лип".
///
/// The incoming instant is canonical UTC (the generated built_value client
/// normalises every wire `DateTime` to UTC); it is converted to the device's
/// local zone here so the DATE reads at the Kyiv wall-clock — a late-evening
/// Kyiv slot is a previous-day date in UTC, so the day/weekday/month must all
/// come from the `.toLocal()` value. See `relative_date.dart` for the same
/// display-layer `.toLocal()` convention.
String formatBookingDayHeader(DateTime day) {
  final DateTime local = day.toLocal();
  final String wd = kWeekdaysUkShort[local.weekday - 1];
  final String mon = kMonthsUkShort[local.month - 1];
  return '$wd, ${local.day} $mon';
}

/// Formats the chosen appointment window, e.g. "вт, 14 лип · 14:00–18:30".
///
/// Both instants are converted to the device local zone first (see
/// [formatBookingDayHeader]) so the date and both times read at the Kyiv
/// wall-clock rather than the raw UTC hour.
String formatBookingWindow(DateTime start, DateTime end) {
  final DateTime startLocal = start.toLocal();
  final DateTime endLocal = end.toLocal();
  final String wd = kWeekdaysUkShort[startLocal.weekday - 1];
  final String mon = kMonthsUkShort[startLocal.month - 1];
  final String s =
      '${_twoDigits(startLocal.hour)}:${_twoDigits(startLocal.minute)}';
  final String e =
      '${_twoDigits(endLocal.hour)}:${_twoDigits(endLocal.minute)}';
  return '$wd, ${startLocal.day} $mon · $s–$e';
}

/// Formats a bare time-of-day as "HH:mm".
///
/// Converts the canonical-UTC instant to the device local zone first so the
/// picker prints the Kyiv wall-clock (09:00), not the raw UTC hour (06:00).
String formatSlotTime(DateTime time) {
  final DateTime local = time.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

/// The chosen day spelled out in full, e.g. "понеділок, 14 липня" — full
/// weekday + day + genitive full month. Used by the booking confirm/success
/// summary cards' full-width "Дата" row so it is never abbreviated or clipped
/// (unlike [formatBookingDayHeader]'s compact chip form).
String formatFullDate(DateTime day) {
  final DateTime local = day.toLocal();
  final String wd = kWeekdaysUkFull[local.weekday - 1];
  final String mon = kMonthsUkGenitive[local.month - 1];
  return '$wd, ${local.day} $mon';
}

/// The booked time range only (no date): [start] → `start +` [totalMinutes],
/// e.g. "14:00–18:30". Used by the booking confirm/success summary cards'
/// "Час" row, paired with [formatFullDate] on its own "Дата" row.
String formatTimeRange(DateTime start, int totalMinutes) {
  // Convert to the device local zone BEFORE adding the duration so both ends
  // read at the Kyiv wall-clock (see [formatSlotTime]).
  final DateTime startLocal = start.toLocal();
  final DateTime endLocal = startLocal.add(Duration(minutes: totalMinutes));
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
String formatStubDayLine(DateTime day) {
  final DateTime local = day.toLocal();
  final String mon = kMonthsUkGenitive[local.month - 1];
  final String wd = kWeekdaysUkShort[local.weekday - 1];
  return '$mon, $wd';
}
