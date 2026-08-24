// Phase 15.1 — WeeklySchedule AsyncNotifier.
//
// Loads and caches the authenticated master's weekly templates (each gap-filled
// to a dense 7-entry ISO week) via [ScheduleRepository.listWeeklySchedules].
// The Phase 15.3 weekly-template editor reads this provider and the calendar
// (15.6) depends on it transitively, so it is [keepAlive: true] — disposing and
// refetching on each navigation would waste bandwidth and flash a loader.
//
// [save] upserts a template atomically (create when [scheduleId] is null, PUT
// otherwise) then re-emits the freshly-loaded list. On success it ALSO
// invalidates every effective-schedule window (see [effectiveScheduleNotifier])
// so the calendar repaints against the new template. A failed save becomes an
// [AsyncError] and performs NO cache invalidation — the calendar keeps showing
// the last good schedule.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../data/schedule_repository_provider.dart';
import '../domain/schedule_model.dart';
import '../domain/weekly_schedule.dart';
import 'effective_schedule_notifier.dart';
import 'schedule_range.dart';

part 'weekly_schedule_notifier.g.dart';

/// Loads and caches the authenticated master's weekly templates.
///
/// Generated provider name: `weeklyScheduleProvider`.
@Riverpod(keepAlive: true)
class WeeklyScheduleNotifier extends _$WeeklyScheduleNotifier {
  static const _tag = 'feature.schedule.weekly';

  @override
  Future<List<WeeklySchedule>> build() {
    return ref.watch(scheduleRepositoryProvider).listWeeklySchedules();
  }

  /// Persists [schedule] (create when [scheduleId] is null, update otherwise),
  /// re-emits the reloaded template list, and invalidates the effective-schedule
  /// cache so the calendar repaints.
  ///
  /// Wraps the work in [AsyncValue.guard] so a thrown [Failure] becomes an
  /// [AsyncError] the screen can render — the notifier never leaks a raw
  /// exception. On failure the effective-schedule cache is left intact.
  Future<void> save(WeeklySchedule schedule, {String? scheduleId}) async {
    if (kDebugMode) {
      log(
        'save: ${scheduleId == null ? 'create' : 'update'} '
        'template scheduleId=$scheduleId',
        name: _tag,
        level: 800,
      );
    }
    state = const AsyncLoading<List<WeeklySchedule>>();
    final result = await AsyncValue.guard(() async {
      // Phase 15.7 — reject an EXPLICIT_TIMES *working* day that carries zero
      // (or misaligned) discrete times BEFORE the network call, so the typed
      // ValidationFailure path is identical whether the client or the backend
      // catches it. INTERVAL days are NOT newly gated here (their validation
      // stays in the editor / DayHours model, unchanged).
      _assertExplicitTimesDaysValid(schedule);
      final repo = ref.read(scheduleRepositoryProvider);
      await repo.upsertWeeklySchedule(schedule, scheduleId: scheduleId);
      // Re-read the authoritative list so the cache reflects exactly what the
      // server now holds (a create may have closed a prior open-ended window).
      return repo.listWeeklySchedules();
    });
    state = result;
    if (result.hasValue) {
      // The template changed — every resolved effective-schedule window is
      // now stale. See [_invalidateEffectiveScheduleWindows]'s doc for why
      // this is no longer a bare family invalidate.
      _invalidateEffectiveScheduleWindows();
    }
  }

  /// Deletes the template identified by [scheduleId], re-emits the reloaded
  /// list, and invalidates the effective-schedule cache.
  Future<void> delete(String scheduleId) async {
    if (kDebugMode) {
      log('delete: scheduleId=$scheduleId', name: _tag, level: 800);
    }
    state = const AsyncLoading<List<WeeklySchedule>>();
    final result = await AsyncValue.guard(() async {
      final repo = ref.read(scheduleRepositoryProvider);
      await repo.deleteWeeklySchedule(scheduleId);
      return repo.listWeeklySchedules();
    });
    state = result;
    if (result.hasValue) {
      _invalidateEffectiveScheduleWindows();
    }
  }

  /// FIX D (mobile-debugger, this track) — the ONE fan-out point for "the
  /// weekly template changed, every resolved `effectiveScheduleProvider`
  /// window is stale", called from BOTH [save] and [delete].
  ///
  /// Used to be a single bare `ref.invalidate(effectiveScheduleProvider)` —
  /// correct in scope (the template really does invalidate every window, so
  /// this can never become a per-range invalidate the way
  /// `booking_calendar_invalidation.dart`'s callers scope to
  /// `affectedDate`(s)) but exposed to the same `ProviderSubscription`-closed
  /// race that file's FIX A/B fix: `MasterScheduleScreen` re-keys its OWN
  /// `ref.watch(effectiveScheduleProvider(_range))` on local `_weekStart`/
  /// `_visibleMonth` state as the master pages weeks/months, so a range
  /// visited earlier this session and paged away from is
  /// pinned-but-unwatched (alive only via `EffectiveScheduleNotifier`'s own
  /// 5-minute `_pinForTtl()` TTL, zero listeners) — precisely the precondition
  /// `invalidateSelf()`'s queued disposal races a later `ref.watch` on. See
  /// `EffectiveScheduleRangeTracker`'s doc (`effective_schedule_notifier
  /// .dart`) for why enumerating the candidates (rather than scoping to one
  /// known range, as the booking fix does) is the correct generalisation
  /// here: `ScheduleRange` is open-ended, so there is no bounded LRU or fixed
  /// enum to fall back on — the tracker exists purely so this loop has a key
  /// set to gate-and-eager-read over, the exact same idiom
  /// `booking_calendar_invalidation.dart` uses.
  ///
  /// Every candidate range costs a `ref.exists` check regardless; only a
  /// range that WAS pinned pays for the eager `ref.read` — a range this
  /// session never visited (and so was never remembered by the tracker) is
  /// never even a candidate.
  void _invalidateEffectiveScheduleWindows() {
    final EffectiveScheduleRangeTracker tracker = ref.read(
      effectiveScheduleRangeTrackerProvider,
    );
    for (final ScheduleRange range in tracker.liveRanges) {
      final bool wasPinned = ref.exists(effectiveScheduleProvider(range));
      // cycle-safe: effectiveScheduleProvider watches overridesProvider + scheduleRepositoryProvider, NOT weeklyScheduleProvider — no back-edge into this notifier, no cycle.
      ref.invalidate(effectiveScheduleProvider(range));
      if (wasPinned) {
        ref.read(effectiveScheduleProvider(range));
      }
    }
  }

  /// Throws [ValidationFailure] if any EXPLICIT_TIMES day that is NOT a day-off
  /// has an empty / misaligned discrete-times list. A day-off (empty times)
  /// passes — "off" is valid in either mode. INTERVAL days are ignored here.
  void _assertExplicitTimesDaysValid(WeeklySchedule schedule) {
    for (final d in schedule.days) {
      if (d.mode != WeekdayMode.explicitTimes || d.isDayOff) continue;
      if (!discreteTimesValid(d.times)) {
        throw const ValidationFailure(fieldErrors: <String, String>{});
      }
    }
  }
}
