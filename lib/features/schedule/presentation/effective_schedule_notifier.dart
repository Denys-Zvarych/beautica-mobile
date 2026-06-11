// Phase 15.1 — EffectiveSchedule family AsyncNotifier (the calendar's data
// source).
//
// Keyed by a bounded [ScheduleRange] (typically one visible month) so each
// window resolves to its own cached provider instance — paging the calendar
// month-by-month fetches each month once and keeps it. The notifier returns the
// resolved [EffectiveDay] list for its range via
// [ScheduleRepository.effectiveSchedule].
//
// Bounded-cache keepAlive (NOT unconditional): after a SUCCESSFUL fetch the
// instance pins itself with `ref.keepAlive()` for [_kRangeCacheTtl] (≈5 min) so
// paging away and BACK to a recently-viewed window (e.g. July → June → July)
// serves the cached data instantly — no AsyncLoading, no loading placeholder.
// A release [Timer] closes the keepAlive link after the TTL, so a year of
// scrolling does NOT pin twelve months of per-day data forever — inactive
// windows still release once the timer fires while unwatched. The timer is
// cancelled on dispose. We pin only on success: a failed/loading fetch is left
// to dispose normally so the next revisit re-fetches (a retry path). The
// current/visible month also stays alive simply because the calendar widget
// keeps watching it.
//
// Cache coherence (reactive): the effective schedule for a range DEPENDS on the
// per-date overrides for that SAME range — `build` `ref.watch`es
// `overridesProvider(range)`. When [OverridesNotifier] reloads the range after a
// successful PUT/DELETE (`overridesProvider` emits the fresh override list),
// this notifier automatically rebuilds and re-fetches the server-resolved
// effective schedule, which now reflects the just-saved override. No manual
// `ref.invalidate(effectiveScheduleProvider)` is needed for an override change —
// the dependency carries the recompute. (Weekly-template saves still invalidate
// explicitly from [WeeklyScheduleNotifier], as those go through a separate
// source that this notifier does not watch.)
//
// Riverpod 3.x seamless-reload note: because `build` re-runs whenever
// `overridesProvider(range)` changes, the new value here is a genuine refetch of
// the effective schedule AFTER the write landed — not a `copyWithPrevious`
// retained snapshot. Awaiting `effectiveScheduleProvider(range).future` on the
// save path therefore resolves to fresh data.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/schedule_repository_provider.dart';
import '../domain/weekly_schedule.dart';
import 'overrides_notifier.dart';
import 'schedule_range.dart';

part 'effective_schedule_notifier.g.dart';

/// How long a successfully-fetched range stays pinned in memory after nothing
/// watches it. Long enough that paging away and back within a normal editing
/// session (July ↔ June) hits the cache and never reloads; short enough that
/// idly scrolling through a year of months does not pin them all indefinitely —
/// each window releases once it has been unwatched for this duration.
const Duration _kRangeCacheTtl = Duration(minutes: 5);

/// Resolves the effective schedule for the dates in [range] (date-only,
/// inclusive). The range MUST be bounded (≤ `kMaxScheduleRangeDays`); the
/// repository asserts and rejects an over-wide window before any network call.
///
/// Generated provider name: `effectiveScheduleProvider` (a family — call
/// `effectiveScheduleProvider(range)`).
@riverpod
class EffectiveScheduleNotifier extends _$EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async {
    // Reactive dependency (the core save-refresh fix): the effective schedule is
    // a server-side composition of the weekly template + the per-date overrides.
    // Watching `overridesProvider(range)` makes this notifier recompute whenever
    // the overrides for this range change — e.g. right after a per-date override
    // is saved/cleared and [OverridesNotifier] reloads the range. We `await` the
    // overrides so the effective-schedule fetch only fires once the fresh
    // override list has resolved (read-after-write ordering on the client),
    // guaranteeing the subsequent `getEffectiveSchedule` reflects the new state.
    //
    // The value is used only as a recompute trigger / ordering gate — the
    // effective schedule itself is the authoritative server projection.
    await ref.watch(overridesProvider(range).future);

    // `range` is date-only by construction (see [ScheduleRange]), so the family
    // key already equals the fetched window — no late normalisation needed.
    final List<EffectiveDay> days = await ref
        .watch(scheduleRepositoryProvider)
        .effectiveSchedule(range.from, range.to);

    // SUCCESS path only (this line is reached only after both awaits resolved):
    // pin the resolved window for [_kRangeCacheTtl] so a revisit serves cached
    // data instantly, then release it. Closing the link does not destroy the
    // instance while it is still watched, and re-running `build` (after a
    // reactive override change or an explicit invalidate) cancels this timer via
    // `onDispose` and re-pins with a fresh TTL — so invalidation and the
    // override save-refresh path are unaffected.
    final link = ref.keepAlive();
    final timer = Timer(_kRangeCacheTtl, link.close);
    ref.onDispose(timer.cancel);

    return days;
  }
}
