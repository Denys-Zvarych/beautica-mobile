// Phase 23.1 — canonical Ukrainian calendar vocabulary (months + weekdays).
//
// Five tables existed, scattered across a `shared/formatters/` name-table
// file, `schedule_model.dart`, `schedule_mapper.dart`,
// `master_schedule_screen.dart` and `booking_date_labels.dart`, reducing to
// five distinct datasets once compared
// literally (see the phase doc, `docs/mobile-phases/phase-214-23.1-uk-calendar-module.md`,
// for the full comparison table). This module is the single canonical home for
// all five, seeded VERBATIM from those sources — lowercase wins wherever two
// occurrences differed only by case, except the nominative months, where both
// existing occurrences already agreed on the Capitalized form.
//
// This phase (23.1) is purely additive: nothing here is imported by any call
// site yet, and none of the five original tables is deleted. 23.2/23.3 migrate
// callers onto this module and retire the duplicates; this file's shape does
// not change when they do.
//
// APOSTROPHE: the two existing full-weekday tables disagreed on Friday's
// apostrophe glyph — `schedule_mapper.dart` used U+2019 (RIGHT SINGLE
// QUOTATION MARK), `booking_date_labels.dart` used U+02BC (MODIFIER LETTER
// APOSTROPHE), the form CLDR specifies for Ukrainian. U+02BC is canonical
// here; `schedule_mapper.dart`'s U+2019 is the one that changes, in 23.2.
//
// Pure Dart: no Flutter import, no `intl` (CLDR) dependency, no `timezone`,
// no `AppLocalizations`. This module answers "what is this month/weekday
// called" only — never "what instant is this" (`shared/time/time_zones.dart`)
// and never "how is this laid out" (call sites). `.arb`/`intl` re-backing was
// evaluated and rejected for this track (see the phase doc's "Why not .arb"
// section) — these tables stay hand-authored permanently.

const List<String> _monthsNominative = <String>[
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

const List<String> _monthsGenitive = <String>[
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

const List<String> _monthsAbbrev = <String>[
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

/// Full Ukrainian weekday names, Monday-first. Friday's apostrophe is
/// U+02BC (MODIFIER LETTER APOSTROPHE) — see this file's header note.
const List<String> _weekdaysFull = <String>[
  'понеділок',
  'вівторок',
  'середа',
  'четвер',
  'пʼятниця',
  'субота',
  'неділя',
];

const List<String> _weekdaysAbbrev = <String>[
  'пн',
  'вт',
  'ср',
  'чт',
  'пт',
  'сб',
  'нд',
];

/// The nominative Ukrainian name of [month], indexed by the 1-based
/// [DateTime.month] (1 = Січень … 12 = Грудень). Throws [RangeError] on an
/// out-of-range index — no clamping, no fallback string.
String monthNominative(int month) => _monthsNominative[month - 1];

/// The genitive Ukrainian name of [month] ("14 січня"), indexed by the
/// 1-based [DateTime.month]. Throws [RangeError] on an out-of-range index.
String monthGenitive(int month) => _monthsGenitive[month - 1];

/// All twelve nominative month names, in calendar order.
///
/// Moved here from its former single-purpose `shared/formatters/` home,
/// retired in Phase 23.2. This is the shape [PeriodRangePickerStrings] wants: the picker
/// takes resolved copy rather than importing a name table itself, exactly as
/// it already does for its weekday captions.
List<String> get monthNamesNominative =>
    List<String>.unmodifiable(_monthsNominative);

/// The 3-letter lowercase Ukrainian abbreviation of [month] ("січ"), indexed
/// by the 1-based [DateTime.month]. Throws [RangeError] on an out-of-range
/// index.
String monthAbbrev(int month) => _monthsAbbrev[month - 1];

/// The full lowercase Ukrainian name of [weekday], indexed by the 1-based
/// [DateTime.weekday] (1 = понеділок … 7 = неділя). Throws [RangeError] on an
/// out-of-range index.
String weekdayName(int weekday) => _weekdaysFull[weekday - 1];

/// The 2-letter lowercase Ukrainian abbreviation of [weekday] ("пн"),
/// indexed by the 1-based [DateTime.weekday]. Throws [RangeError] on an
/// out-of-range index.
String weekdayAbbrev(int weekday) => _weekdaysAbbrev[weekday - 1];

/// Upper-cases [s] in full ("січ" -> "СІЧ"). Applied at the call site that
/// needs the upper variant — deliberately not baked into a separate
/// accessor; see this file's header note.
String ukUpper(String s) => s.toUpperCase();

/// Capitalizes only the first character of [s] ("пн" -> "Пн"), leaving the
/// rest untouched. Applied at the call site that needs the capitalized
/// variant — deliberately not baked into a separate accessor; see this
/// file's header note.
String ukCapitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
