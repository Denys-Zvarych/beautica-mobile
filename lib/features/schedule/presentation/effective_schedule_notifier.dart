// Phase 15.1 — EffectiveSchedule family AsyncNotifier (the calendar's data
// source).
//
// Keyed by a bounded [ScheduleRange] (typically one visible month) so each
// window resolves to its own cached provider instance — paging the calendar
// month-by-month fetches each month once and keeps it. The notifier returns the
// resolved [EffectiveDay] list for its range via
// [ScheduleRepository.effectiveSchedule].
//
// NOT keepAlive: windows the user has paged away from should release once
// nothing watches them (a year of scrolling shouldn't pin twelve months of
// per-day data forever). The current/visible month stays alive because the
// calendar widget keeps watching it.
//
// Cache coherence: [WeeklyScheduleNotifier] and [OverridesNotifier]
// `ref.invalidate(effectiveScheduleNotifierProvider)` on every successful save,
// so a template or override change repaints every resolved window.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/schedule_repository_provider.dart';
import '../domain/weekly_schedule.dart';
import 'schedule_range.dart';

part 'effective_schedule_notifier.g.dart';

/// Resolves the effective schedule for the dates in [range] (date-only,
/// inclusive). The range MUST be bounded (≤ `kMaxScheduleRangeDays`); the
/// repository asserts and rejects an over-wide window before any network call.
///
/// Generated provider name: `effectiveScheduleProvider` (a family — call
/// `effectiveScheduleProvider(range)`).
@riverpod
class EffectiveScheduleNotifier extends _$EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) {
    // `range` is date-only by construction (see [ScheduleRange]), so the family
    // key already equals the fetched window — no late normalisation needed.
    return ref
        .watch(scheduleRepositoryProvider)
        .effectiveSchedule(range.from, range.to);
  }
}
