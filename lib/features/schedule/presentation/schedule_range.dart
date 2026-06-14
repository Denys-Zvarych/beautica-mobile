// Phase 15.1 — ScheduleRange: a bounded, date-only `[from, to]` window used as
// the family key for the effective-schedule and overrides notifiers.
//
// A freezed value object so two ranges with the same from/to dates are equal —
// essential for Riverpod family caching (the same visible month must resolve to
// the same provider instance rather than re-fetching on every rebuild).
//
// Normalisation happens AT CONSTRUCTION: the public [ScheduleRange] factory and
// [ScheduleRange.month] both truncate `from`/`to` to local midnight (date-only).
// This means every instance is pre-normalised, so the freezed family key equals
// the window actually fetched — a range built from a `DateTime.now()` (which
// carries wall-clock time) keys identically to one built from a midnight date.
// Without construction-time truncation the family cache would thrash and fire
// duplicate network fetches for what is logically the same month.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'schedule_range.freezed.dart';

/// An inclusive, date-only `[from, to]` window.
///
/// Both bounds are always local-midnight date-only — the public factory strips
/// any time-of-day, so two ranges covering the same dates are always equal
/// regardless of how the caller's `DateTime`s were built.
@freezed
abstract class ScheduleRange with _$ScheduleRange {
  /// Builds a date-only `[from, to]` window, truncating any time-of-day from
  /// both bounds so the family key is stable by construction.
  factory ScheduleRange({required DateTime from, required DateTime to}) =>
      ScheduleRange.raw(
        from: DateTime(from.year, from.month, from.day),
        to: DateTime(to.year, to.month, to.day),
      );

  /// Pass-through freezed constructor for already-date-only bounds. NOT
  /// underscore-prefixed: freezed derives its `map`/`when` callback parameter
  /// names from the factory name, and a leading underscore emits illegal Dart
  /// (a named parameter cannot start with `_`). Callers normally go through the
  /// normalising [ScheduleRange] factory above (or [ScheduleRange.month]); this
  /// is used internally once both bounds are confirmed date-only.
  const factory ScheduleRange.raw({
    required DateTime from,
    required DateTime to,
  }) = _ScheduleRange;

  const ScheduleRange._();

  /// A range covering the whole calendar month containing [anyDayInMonth]
  /// (first day → last day of that month, date-only).
  factory ScheduleRange.month(DateTime anyDayInMonth) {
    final from = DateTime(anyDayInMonth.year, anyDayInMonth.month);
    // Day 0 of the next month == the last day of this month.
    final to = DateTime(anyDayInMonth.year, anyDayInMonth.month + 1, 0);
    // Both bounds are already date-only; route through `raw` to skip the
    // redundant truncation in the public factory.
    return ScheduleRange.raw(from: from, to: to);
  }

  /// No-op alias kept for call-site compatibility: every [ScheduleRange] is
  /// already date-only at construction, so this returns the same logical value.
  ScheduleRange get normalised => this;
}
