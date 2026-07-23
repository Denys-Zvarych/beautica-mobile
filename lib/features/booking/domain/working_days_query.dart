// Phase 14.14 — WorkingDaysQuery: a bounded, date-only `[from, to]` window
// FOR A GIVEN MASTER — the family key for [workingDaysProvider].
//
// Deliberately mirrors `schedule/presentation/schedule_range.dart`'s
// normalise-at-construction shape (so paging month-by-month resolves to a
// stable family instance instead of thrashing), but is NOT that type: this
// query is masterId-parameterized on purpose. `ScheduleRange` /
// `effectiveScheduleProvider` are intentionally hard-wired to "my own
// schedule only" via `masterProfileProvider` (a different feature's
// presentation layer, which booking must not import per the feature-import
// boundary — cross-feature imports go through `domain/`/`shared/` only), and
// the booking flow's calendar needs an ARBITRARY master's working days. A
// freezed value type here (rather than reaching for `ScheduleRange`) keeps
// this family key inside the booking feature and ready to key the salon
// multi-master step-3 time picker later (still a Phase 14.13 placeholder
// today — not wired up yet) without any rework.
//
// Normalisation happens AT CONSTRUCTION: the public [WorkingDaysQuery]
// factory and [WorkingDaysQuery.month] both truncate `from`/`to` to local
// midnight (date-only), so two windows covering the same calendar dates for
// the same master are always `==`-equal — essential for Riverpod family
// caching.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'working_days_query.freezed.dart';

/// An inclusive, date-only `[from, to]` window scoped to [masterId].
///
/// The optional [serviceId] selects the backend's `working-days` MODE
/// (Phase 14.20): when non-null, each day's `working` flag means "a free range
/// fits THIS service's full duration with start >= now+15min" — the SAME
/// availability computation the `/slots` endpoint runs, so the calendar's
/// day-enabled gate can no longer disagree with the time grid (the pre-fix bug:
/// a day shown selectable that then had zero bookable slots). When [serviceId]
/// is null the flag is the older SCHEDULE-SHAPE signal ("master has intervals
/// that day", duration-blind) — the mode the salon step-3 per-master picker
/// ([MasterSchedulePage]) still keys on today. Because [serviceId] participates
/// in `==`/`hashCode`, the two modes resolve to DISTINCT `workingDaysProvider`
/// family members and never share a cache entry.
@freezed
abstract class WorkingDaysQuery with _$WorkingDaysQuery {
  /// Builds a date-only `[from, to]` window, truncating any time-of-day from
  /// both bounds so the family key is stable by construction. Pass [serviceId]
  /// to request the availability-aware mode (see the class doc).
  factory WorkingDaysQuery({
    required String masterId,
    required DateTime from,
    required DateTime to,
    String? serviceId,
  }) => WorkingDaysQuery.raw(
    masterId: masterId,
    from: DateTime(from.year, from.month, from.day),
    to: DateTime(to.year, to.month, to.day),
    serviceId: serviceId,
  );

  /// Pass-through freezed constructor for already-date-only bounds. Not
  /// underscore-prefixed for the same reason as `ScheduleRange.raw`: freezed
  /// derives its `map`/`when` parameter names from the factory name, and a
  /// leading underscore is illegal there. Callers normally go through the
  /// normalising [WorkingDaysQuery] factory above (or [WorkingDaysQuery.month]).
  const factory WorkingDaysQuery.raw({
    required String masterId,
    required DateTime from,
    required DateTime to,
    String? serviceId,
  }) = _WorkingDaysQuery;

  const WorkingDaysQuery._();

  /// A window covering the whole calendar month containing [anyDayInMonth]
  /// (first day → last day of that month, date-only) for [masterId]. Pass
  /// [serviceId] to request the availability-aware mode (see the class doc);
  /// omit it for the schedule-shape mode.
  factory WorkingDaysQuery.month({
    required String masterId,
    required DateTime anyDayInMonth,
    String? serviceId,
  }) {
    final DateTime from = DateTime(anyDayInMonth.year, anyDayInMonth.month);
    // Day 0 of the next month == the last day of this month.
    final DateTime to = DateTime(
      anyDayInMonth.year,
      anyDayInMonth.month + 1,
      0,
    );
    // Both bounds are already date-only; route through `raw` to skip the
    // redundant truncation in the public factory.
    return WorkingDaysQuery.raw(
      masterId: masterId,
      from: from,
      to: to,
      serviceId: serviceId,
    );
  }
}
