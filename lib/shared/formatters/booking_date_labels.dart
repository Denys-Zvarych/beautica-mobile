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

String _twoDigits(int v) => v.toString().padLeft(2, '0');

/// Formats [day] as a compact day-header chip label, e.g. "пн, 14 лип".
String formatBookingDayHeader(DateTime day) {
  final String wd = kWeekdaysUkShort[day.weekday - 1];
  final String mon = kMonthsUkShort[day.month - 1];
  return '$wd, ${day.day} $mon';
}

/// Formats the chosen appointment window, e.g. "вт, 14 лип · 14:00–18:30".
String formatBookingWindow(DateTime start, DateTime end) {
  final String wd = kWeekdaysUkShort[start.weekday - 1];
  final String mon = kMonthsUkShort[start.month - 1];
  final String s = '${_twoDigits(start.hour)}:${_twoDigits(start.minute)}';
  final String e = '${_twoDigits(end.hour)}:${_twoDigits(end.minute)}';
  return '$wd, ${start.day} $mon · $s–$e';
}

/// Formats a bare time-of-day as "HH:mm".
String formatSlotTime(DateTime time) =>
    '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
