// Phase 6.1 — WorkingHours AsyncNotifier.
//
// Loads and caches the authenticated master's working week (always 7 ordered
// entries, gap-filled by the mapper) via [WorkingHoursRepository.list]. The
// editor (Phase 6.2) reads this provider; the calendar (Phase 6.3/6.4) reads it
// on every paint, so it is [keepAlive: true] — disposing and refetching on each
// navigation would waste bandwidth and flash a loader on the calendar.
//
// [list] is a NETWORK read (`getWeeklySchedules`) since the weekly-schedule
// migration (Phase 6.2): working hours are no longer bundled on the [Master]
// profile envelope (`master_mapper.dart` sets `workingHours: const []`), so
// there is no profile-cache coherence to maintain here. [build] watches only the
// Master-row id (via [workingHoursRepositoryProvider]), so an unrelated profile
// invalidation (a bio edit, a locality change) does NOT re-run [list].
//
// [save] commits the whole week atomically via [WorkingHoursRepository.replaceAll]
// and writes the server-confirmed (gap-filled) week straight into [state]. It
// deliberately does NOT invalidate [masterProfileProvider]: the profile no
// longer carries working hours, so a post-write profile GET + re-[list] would be
// pure waste (a redundant `/weekly-schedules` round-trip and a loader flash) with
// the authoritative result already in [state].

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/working_hours_repository_provider.dart';
import '../domain/working_hours.dart';

part 'working_hours_notifier.g.dart';

/// Loads and caches the authenticated master's working week.
///
/// Generated provider name: `workingHoursNotifierProvider`.
@Riverpod(keepAlive: true)
class WorkingHoursNotifier extends _$WorkingHoursNotifier {
  static const _tag = 'feature.calendar.workinghours';

  @override
  Future<List<WorkingHours>> build() {
    // [list] is a network read (`getWeeklySchedules`). The repository provider
    // watches only the Master-row id, so this rebuilds when the authenticated
    // master changes but NOT on an unrelated profile invalidation.
    return ref.watch(workingHoursRepositoryProvider).list();
  }

  /// Persists the whole week and emits the server-confirmed result.
  ///
  /// Wraps the save in [AsyncValue.guard] so a thrown [Failure] becomes an
  /// [AsyncError] the screen can render — the notifier never leaks a raw
  /// exception. [replaceAll] returns the saved (server-confirmed, gap-filled)
  /// 7-entry week, which is written straight into [state]; there is no follow-up
  /// profile invalidation or re-[list] (the profile no longer carries working
  /// hours, so a post-write GET would be redundant work and a loader flash).
  Future<void> save(List<WorkingHours> hours) async {
    if (kDebugMode) {
      log(
        'save: replacing week with ${hours.length} entries',
        name: _tag,
        level: 800,
      );
    }
    state = const AsyncLoading<List<WorkingHours>>();
    // [replaceAll] does GET(pick) + PUT/POST and returns the authoritative week;
    // that result is the new state — no extra profile GET, no re-list.
    state = await AsyncValue.guard(
      () => ref.read(workingHoursRepositoryProvider).replaceAll(hours),
    );
  }
}
