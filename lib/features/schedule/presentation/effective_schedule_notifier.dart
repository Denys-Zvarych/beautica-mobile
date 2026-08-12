// Phase 15.1 — EffectiveSchedule family AsyncNotifier (the calendar's data
// source).
//
// Keyed by a bounded [ScheduleRange] (typically one visible month) so each
// window resolves to its own cached provider instance — paging the calendar
// month-by-month fetches each month once and keeps it. The notifier returns the
// resolved [EffectiveDay] list for its range via
// [ScheduleRepository.effectiveSchedule].
//
// Bounded-cache keepAlive (NOT unconditional): after a SUCCESSFUL fetch, OR a
// build that short-circuits to the last resolved page (see the mobile-perf
// MEDIUM follow-up below), the instance pins itself with `ref.keepAlive()`
// for [_kRangeCacheTtl] (≈5 min) — via the shared [_pinForTtl] helper — so
// paging away and BACK to a recently-viewed window (e.g. July → June → July)
// serves the cached data instantly — no AsyncLoading, no loading placeholder.
// A release [Timer] closes the keepAlive link after the TTL, so a year of
// scrolling does NOT pin twelve months of per-day data forever — inactive
// windows still release once the timer fires while unwatched. The timer is
// cancelled on dispose. BOTH completing paths must re-pin on every build,
// because Riverpod releases a build's `keepAlive()` link the moment that
// build is superseded by the next one — a build that reaches its return
// without calling [_pinForTtl] finishes with zero active pins (mobile-qa
// MEDIUM fix 2026-08-12; the short-circuit used to skip this, silently
// defeating the TTL cache). We pin only on a resolved page (fetched or
// cached): a failed/loading fetch is left to dispose normally so the next
// revisit re-fetches (a retry path). The current/visible month also stays
// alive simply because the calendar widget keeps watching it.
//
// Cache coherence (reactive): the effective schedule for a range DEPENDS on the
// per-date overrides for that SAME range — `build` `ref.watch`es
// `overridesProvider(range)`. When [OverridesNotifier] reloads the range after a
// successful PUT/DELETE (`overridesProvider` emits the fresh override list),
// this notifier automatically rebuilds and re-fetches the server-resolved
// effective schedule, which now reflects the just-saved override. (Weekly-
// template saves still invalidate explicitly from [WeeklyScheduleNotifier], as
// those go through a separate source that this notifier does not watch.)
//
// Cross-range coherence (revision event): the above only covers a write under
// the SAME `range` this instance is keyed to. `overridesProvider` and this
// provider are both families keyed on the exact [ScheduleRange], so a write
// under a different range for an overlapping date (e.g. the month-spanning
// schedule editor vs. a single-day range watched by «Мої записи») is a distinct
// family instance that the reactive watch above never reaches — it would stay
// pinned stale by its own `ref.keepAlive()` until the TTL lapses. `build` also
// watches [overridesRevisionProvider], which [OverridesNotifier] bumps after
// EVERY successful write regardless of range; that watch is what forces this
// (and every other live) window to RECOMPUTE `build`. It cannot be an
// `ref.invalidate(effectiveScheduleProvider)` call from [OverridesNotifier]
// instead, because this `build` already watches `overridesProvider` — that
// would be a real watch cycle, not a one-way edge — see
// `overrides_revision_provider.dart`'s header for the full reasoning.
//
// mobile-perf MEDIUM follow-up — recompute is not the same as refetch: a
// bumped [overridesRevisionProvider] reruns THIS `build`, but a write at a
// range that shares no date with `range` (e.g. a different month entirely)
// has nothing new for this window to learn. `build` compares the bump's
// carried [ScheduleRange] against `range` via [ScheduleRange.overlaps] and,
// when they provably do not overlap AND `overridesProvider(range)`'s own
// awaited value is unchanged (see `_lastOverridesSeen` below), returns the
// last resolved page straight back out instead of calling
// `ScheduleRepository.effectiveSchedule` again. A master who paged through
// several months and days no longer fires a concurrent, uncoalesced refetch
// across all of them on one unrelated save. An OVERLAPPING write (including
// the trivial same-range case, which also always changes `overridesProvider
// (range)`'s awaited value) still refetches — see [ScheduleRange.overlaps]'s
// doc for why this must be an overlap test, not an equality test.
//
// Riverpod 3.x seamless-reload note: because `build` re-runs whenever
// `overridesProvider(range)` changes, the new value here is a genuine refetch of
// the effective schedule AFTER the write landed — not a `copyWithPrevious`
// retained snapshot. Awaiting `effectiveScheduleProvider(range).future` on the
// save path therefore resolves to fresh data.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/schedule_repository_provider.dart';
import '../domain/schedule_model.dart';
import '../domain/weekly_schedule.dart';
import 'overrides_notifier.dart';
import 'overrides_revision_provider.dart';
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
  /// The last `overridesProvider(range)`-awaited value this instance saw,
  /// compared by IDENTITY in [build] below — mirrors
  /// `bookings_discovery_view.dart`'s `_visibleBookingsFor` cache fields:
  /// plain instance fields on the (long-lived, `keepAlive`d) notifier
  /// object, NOT part of Riverpod's own `AsyncValue` machinery, so the
  /// short-circuit below cannot be tripped up by how `state` itself behaves
  /// mid-rebuild. `ScheduleRepository.listOverrides` — and the `_mutate`
  /// reload after a same-range write — hand out a FRESH `List` instance on
  /// every genuine fetch, so identity is a true "did MY range's own
  /// overrides change" signal, independent of [overridesRevisionProvider].
  /// Reset to `null` implicitly whenever a fresh notifier instance is
  /// created (after a dispose — e.g. the TTL lapsing), which is correct: a
  /// brand-new instance has no prior page to reuse and must fetch once
  /// regardless.
  List<ScheduleOverride>? _lastOverridesSeen;

  /// The last successfully resolved page for `range` — see
  /// [_lastOverridesSeen]'s doc for why this lives outside `AsyncValue`.
  /// Returned as-is by [build]'s short-circuit below instead of calling
  /// [ScheduleRepository.effectiveSchedule] again.
  List<EffectiveDay>? _lastDays;

  /// mobile-perf MEDIUM follow-up (F3 fix's own race) — bumped at the TOP of
  /// every [build] invocation, before either `await`. Riverpod re-invokes
  /// `build` on this SAME live instance when a watched dependency changes
  /// (`overridesProvider(range)` or [overridesRevisionProvider]) without
  /// cancelling or awaiting a prior in-flight invocation — Dart futures run
  /// to completion regardless. Two builds of this instance can therefore be
  /// in flight at once (e.g. two rapid writes touching this range, via
  /// `putSpan`'s chunked concurrent PUTs or a double-tap save), and the
  /// OLDER one's `await`s can resolve AFTER the newer one has already
  /// written fresher values into [_lastOverridesSeen] / [_lastDays].
  /// Riverpod's own `state` machinery protects `state` against a superseded
  /// `build()` completing late; it does NOT extend to these plain instance
  /// fields. Each `build` call captures its OWN generation into a local
  /// (`myGen` below) at entry; every write to [_lastOverridesSeen] or
  /// [_lastDays] is guarded by `myGen == _buildGen` at the point of the
  /// write, so a stale build's tail can never clobber a newer build's
  /// result — it simply writes nothing and its (unused, because Riverpod
  /// already discards it) return value is inert. Reset to `0` implicitly
  /// whenever a fresh notifier instance is created, same as
  /// [_lastOverridesSeen] / [_lastDays].
  int _buildGen = 0;

  /// Pins this instance alive for [_kRangeCacheTtl] — called from BOTH the
  /// cache-hit short-circuit and the real-fetch success path in [build] so
  /// every completed build ends with exactly one live pin.
  ///
  /// mobile-qa MEDIUM fix: `ref.keepAlive()`'s link is scoped to the build
  /// that opened it — Riverpod releases a build's own links the moment that
  /// build is superseded by a new one (e.g. `overridesRevisionProvider`
  /// bumping on an unrelated write). Only the real-fetch path used to call
  /// this, so a rebuild that took the cache-hit short-circuit finished with
  /// NO active pin at all (the previous build's link already released, and
  /// no new one opened) — if nothing happened to be watching that instant,
  /// autoDispose tore it down and silently recreated it on the next read,
  /// defeating the 5-minute TTL cache this header promises.
  ///
  /// Lifecycle per call: opens one [KeepAliveLink], starts one [Timer] that
  /// closes it after [_kRangeCacheTtl], and registers [Ref.onDispose] to
  /// cancel that [Timer]. `onDispose` fires (cancelling the Timer) whenever
  /// THIS build is superseded, so a stale build can never leave a pending
  /// [Timer] behind; the link itself either closes on TTL expiry or is
  /// released by Riverpod's own supersession handling — never both, and
  /// never neither.
  void _pinForTtl() {
    final link = ref.keepAlive();
    final timer = Timer(_kRangeCacheTtl, link.close);
    ref.onDispose(timer.cancel);
  }

  @override
  Future<List<EffectiveDay>> build(ScheduleRange range) async {
    final int myGen = ++_buildGen;

    // Reactive dependency (the core save-refresh fix): the effective schedule is
    // a server-side composition of the weekly template + the per-date overrides.
    // Watching `overridesProvider(range)` makes this notifier recompute whenever
    // the overrides for this range change — e.g. right after a per-date override
    // is saved/cleared and [OverridesNotifier] reloads the range. We `await` the
    // overrides so the effective-schedule fetch only fires once the fresh
    // override list has resolved (read-after-write ordering on the client),
    // guaranteeing the subsequent `getEffectiveSchedule` reflects the new state.
    final List<ScheduleOverride> overrides = await ref.watch(
      overridesProvider(range).future,
    );
    // Compared against whatever the MOST RECENT non-stale build last wrote —
    // see [_buildGen]'s doc: a stale build's own write below is skipped, so
    // `_lastOverridesSeen` here can only ever hold a value written by a build
    // that was still current at the time it wrote.
    final bool overridesChanged = !identical(_lastOverridesSeen, overrides);
    if (myGen == _buildGen) {
      _lastOverridesSeen = overrides;
    }

    // Cross-range trigger — see the header comment above. Any override write
    // at ANY range bumps this, carrying the WRITTEN [ScheduleRange], forcing
    // THIS instance (and every other live effective-schedule window) to
    // recompute `build` even though the write happened under a different
    // [ScheduleRange] than `range`.
    final OverridesRevisionEvent revision = ref.watch(
      overridesRevisionProvider,
    );
    final ScheduleRange? writtenRange = revision.writtenRange;
    // `null` only for the provider's never-bumped initial state, which never
    // reaches here on anything but the very first build of the whole app
    // session — treated as "overlaps" (never skip) so it can never
    // accidentally suppress a legitimate first fetch.
    final bool revisionOverlapsRange =
        writtenRange == null || writtenRange.overlaps(range);

    // The short-circuit (mobile-perf MEDIUM fix): recompute was forced by a
    // `overridesRevisionProvider` bump, but this range's own OWN overrides
    // are provably unchanged (`!overridesChanged`) AND the bump's write
    // provably touched no date this range covers (`!revisionOverlapsRange`)
    // — nothing relevant to `range` happened, so hand back the last resolved
    // page instead of re-hitting the network. A same-range write always
    // trips `overridesChanged` (its reload always yields a fresh `List`
    // instance), and any OVERLAPPING cross-range write always trips
    // `revisionOverlapsRange` — either alone is enough to fall through to a
    // real fetch below, so this can never suppress a needed refetch.
    final List<EffectiveDay>? cached = _lastDays;
    if (!overridesChanged && !revisionOverlapsRange && cached != null) {
      // Re-pin: this build superseded the one that opened the previous
      // link (Riverpod already released that link the moment this build
      // started), so without this call the instance would be returning to
      // an unwatched caller with zero active pins — see [_pinForTtl]'s doc.
      _pinForTtl();
      return cached;
    }

    // `range` is date-only by construction (see [ScheduleRange]), so the family
    // key already equals the fetched window — no late normalisation needed.
    final List<EffectiveDay> days = await ref
        .watch(scheduleRepositoryProvider)
        .effectiveSchedule(range.from, range.to);

    // SUCCESS path only (this line is reached only after both awaits resolved):
    // pin the resolved window for [_kRangeCacheTtl] so a revisit serves cached
    // data instantly — see [_pinForTtl]'s doc for the full lifecycle. Closing
    // the link does not destroy the instance while it is still watched, and
    // re-running `build` (after a reactive override change or an explicit
    // invalidate) re-pins with a fresh TTL via this same call — so invalidation
    // and the override save-refresh path are unaffected.
    _pinForTtl();

    // Guarded for the same reason as `_lastOverridesSeen` above: if a NEWER
    // build already completed and wrote a fresher page while this (now
    // stale) build was awaiting the network above, this write is skipped so
    // it cannot overwrite the newer result with older data.
    if (myGen == _buildGen) {
      _lastDays = days;
    }
    return days;
  }
}
