// Ukrainian month names in the **nominative** case, shared across features.
//
// Lifted out of `features/schedule/domain/schedule_model.dart` (Phase 15.5) in
// Phase 7.7, when the range calendar moved to `shared/widgets/` and acquired a
// SECOND caller in the booking feature. A `shared/` widget must not reach into
// a feature's `domain/`, and booking must not reach into schedule's — so the
// one thing both need lives here. `schedule_model.dart` now re-exports
// [monthNominative] so every existing schedule call site is untouched.
//
// Not localised, deliberately and consistently with the rest of this layer:
// the app is UA-primary and every sibling date formatter in `schedule_model`
// is a hard-coded Ukrainian table. This table is superseded by the canonical
// `shared/formatters/uk_calendar.dart` (track 23, phase 23.1); this file is
// retired once its callers migrate (23.2), not promoted to `.arb` — track 23
// ends at 23.3, and the calendar tables stay hand-authored permanently.
//
// Pure Dart: no Flutter imports.

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

/// The nominative Ukrainian name of [month], indexed by the 1-based
/// [DateTime.month] (1 = Січень … 12 = Грудень).
String monthNominative(int month) => _monthsNominative[month - 1];

/// All twelve nominative month names, in calendar order.
///
/// The shape [PeriodRangePickerStrings] wants: the picker takes resolved copy
/// rather than importing a name table itself, exactly as it already does for
/// its weekday captions.
List<String> get monthNamesNominative =>
    List<String>.unmodifiable(_monthsNominative);
