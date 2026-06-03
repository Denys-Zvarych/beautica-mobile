// Phase 6.1 — WorkingHours AsyncNotifier.
//
// Loads and caches the authenticated master's working week (always 7 ordered
// entries, gap-filled by the mapper) via [WorkingHoursRepository.list]. The
// editor (Phase 6.2) reads this provider; the calendar (Phase 6.3/6.4) reads it
// on every paint, so it is [keepAlive: true] — disposing and refetching on each
// navigation would waste bandwidth and flash a loader on the calendar.
//
// PERF M2 (cache coherence): the canonical working week lives on the cached
// [Master] profile. [build] watches [workingHoursRepositoryProvider] (which in
// turn watches [masterProfileProvider]), so any profile invalidation — a
// profile edit, a locality change, or a working-hours save — propagates here
// and the week is re-derived from the fresh profile rather than going stale.
//
// [save] commits the whole week atomically via [WorkingHoursRepository.replaceAll]
// then invalidates [masterProfileProvider] so the authoritative server response
// is folded back into the profile cache; that invalidation flows through
// [build] and re-emits the saved (server-confirmed, gap-filled) list to every
// watcher.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../master/presentation/master_profile_notifier.dart';
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
    // ref.watch (PERF M2): workingHoursRepositoryProvider rebuilds whenever the
    // cached master profile is invalidated, so a profile refresh propagates the
    // fresh week here instead of leaving this notifier stale. [list] is a pure
    // cache read (no network call) per PERF M1.
    return ref.watch(workingHoursRepositoryProvider).list();
  }

  /// Persists the whole week and folds the server-confirmed result back into
  /// the profile cache.
  ///
  /// Wraps the save in [AsyncValue.guard] so a thrown [Failure] becomes an
  /// [AsyncError] the screen can render — the notifier never leaks a raw
  /// exception. On success it invalidates [masterProfileProvider] so the
  /// canonical profile re-fetches with the saved week; that invalidation flows
  /// back through [build] and re-emits the gap-filled 7-entry list to every
  /// watcher.
  Future<void> save(List<WorkingHours> hours) async {
    if (kDebugMode) {
      log(
        'save: replacing week with ${hours.length} entries',
        name: _tag,
        level: 800,
      );
    }
    state = const AsyncLoading<List<WorkingHours>>();
    final result = await AsyncValue.guard(
      () => ref.read(workingHoursRepositoryProvider).replaceAll(hours),
    );
    // Surface the optimistic server-confirmed list immediately …
    state = result;
    // … then refresh the canonical profile cache so the working hours carried on
    // [Master] stay coherent with what was just persisted (PERF M2). The
    // resulting rebuild of [build] re-emits the same authoritative week.
    if (result.hasValue) {
      ref.invalidate(masterProfileProvider);
    }
  }
}
