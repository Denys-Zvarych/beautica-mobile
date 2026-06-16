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
      // The template changed — every resolved effective-schedule window is now
      // stale. Invalidate the whole family so the calendar re-fetches.
      ref.invalidate(effectiveScheduleProvider);
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
      ref.invalidate(effectiveScheduleProvider);
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
