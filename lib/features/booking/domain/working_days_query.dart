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
/// The optional [serviceIds] selects the backend's `working-days` MODE
/// (Phase 14.20 / MO-2): when non-null it is an ORDERED, non-empty list and
/// each day's `working` flag means "a free range fits the SUMMED duration of
/// THESE services with start >= now+15min" — the SAME availability computation
/// the `/slots` endpoint runs, so the calendar's day-enabled gate can no longer
/// disagree with the time grid (the pre-fix bug: a day shown selectable that
/// then had zero bookable slots). A single-element list is the single-service
/// path. When [serviceIds] is null the flag is the older SCHEDULE-SHAPE signal
/// ("master has intervals that day", duration-blind) — a mode NO live caller
/// uses any more: both pickers are availability-aware, the independent-master
/// one (`SlotDateScreen`) passing the visit's ordered service ids and the salon
/// step-3 one (`MasterSchedulePage`) passing the ordered per-master assignment
/// ids. The null mode is retained only as the type's default and for the
/// equality tests that pin the two modes apart. Because
/// [serviceIds] is a freezed collection field it participates in `==`/`hashCode`
/// (deep equality), so the two modes — and different service selections —
/// resolve to DISTINCT `workingDaysProvider` family members and never share a
/// cache entry, while a stable one-element list keeps the single-service cache
/// behaviour unchanged.
@freezed
abstract class WorkingDaysQuery with _$WorkingDaysQuery {
  /// Builds a date-only `[from, to]` window, truncating any time-of-day from
  /// both bounds so the family key is stable by construction. Pass [serviceIds]
  /// to request the availability-aware mode (see the class doc).
  factory WorkingDaysQuery({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
  }) => WorkingDaysQuery.raw(
    masterId: masterId,
    from: DateTime(from.year, from.month, from.day),
    to: DateTime(to.year, to.month, to.day),
    serviceIds: serviceIds,
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
    List<String>? serviceIds,
  }) = _WorkingDaysQuery;

  const WorkingDaysQuery._();

  /// A window covering the whole calendar month containing [anyDayInMonth]
  /// (first day → last day of that month, date-only) for [masterId]. Pass
  /// [serviceIds] to request the availability-aware mode (see the class doc);
  /// omit it for the schedule-shape mode.
  factory WorkingDaysQuery.month({
    required String masterId,
    required DateTime anyDayInMonth,
    List<String>? serviceIds,
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
      serviceIds: serviceIds,
    );
  }
}
