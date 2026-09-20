// Phase 335 — SalonEffectiveSchedule family AsyncNotifier: the salon «Записи»
// board's working-hours data source.
//
// Keyed by `(salonId, ScheduleRange)`. The board asks for exactly ONE MONTH
// (`ScheduleRange.month(day)`), never one day: the batch endpoint fans out
// across the whole roster, so a per-day key would issue one roster-wide fan-out
// per rail chip tap. One month covers every day the rail can reach without a
// second request, and paging back to a month visited within the TTL below
// serves it from cache.
//
// ## Deliberately NOT a clone of `effective_schedule_notifier.dart`
//
// That notifier carries three mechanisms this one does not, and each absence is
// a decision rather than an omission:
//
//   * NO `overridesProvider` watch and NO `overridesRevisionProvider` watch.
//     Both are keyed on [ScheduleScope] — a per-MASTER key. This provider is
//     salon-wide and has no such key (see [SalonRosterScheduleRepository]'s doc
//     for why bending `ScheduleScope` to carry a salon-only shape was rejected).
//     The consequence is honest and small: an override written from the salon
//     schedule editor does not push into a board that is already open. The board
//     re-fetches on its next mount or once the TTL below lapses, and the data it
//     is stale about is ADORNMENT (the timeline's top and bottom), never a
//     booking. Contrast the master calendar, where the same staleness would
//     mis-state which days are bookable.
//   * NO `EffectiveScheduleRangeTracker` registration. That tracker exists to
//     enumerate keys for the wasPinned-gated bare-family invalidation
//     `WeeklyScheduleNotifier` and `AuthNotifier.logout` perform on
//     `effectiveScheduleProvider`. Nothing invalidates THIS family by bare
//     name, so there is no key set to enumerate.
//   * NO cross-range short-circuit. That optimisation exists because a
//     revision bump force-recomputes every live window; with no revision watch
//     here, `build` only re-runs on a genuine invalidate.
//
// ## TTL keepAlive — mirrors `effective_schedule_notifier.dart:93`
//
// After a SUCCESSFUL fetch the instance pins itself with `ref.keepAlive()` for
// [_kSalonRangeCacheTtl] (5 min), released by a [Timer] that `ref.onDispose`
// cancels. Paging the board away and back inside a session therefore serves
// cached hours with no reload; a day of idle paging does not pin twelve months
// of roster-wide data forever. A failed fetch is deliberately left unpinned so
// the next visit retries.
//
// Unlike its master-scoped sibling this notifier has only ONE completing path
// (there is no cache-hit short-circuit), so the "both paths must re-pin" rule
// that fix guards against cannot apply here.
//
// The pin is BOUNDED by [SalonScheduleKeepAliveLru] (3 windows,
// `salon_schedule_keep_alive_lru.dart`), which owns the TTL timer. At today's
// key — Kyiv-today's month, one member per salon — the budget is never
// reached and evicts nothing; it exists so that the named `onDayChanged`
// re-key, which would make members multiply per month reached, cannot silently
// unbound the cache. See the boxed note at the `ref.keepAlive()` call below.
//
// ## Session boundary
//
// `AuthNotifier.logout` bare-invalidates this family. Neither of the key's two
// components carries the authenticated identity and nothing in the chain
// (`salonRosterScheduleRepositoryProvider` → `scheduleSalonApiProvider` →
// `dioProvider`) watches `authProvider`, so without that sweep a logout→login
// on the same salon tablet would be served the outgoing session's roster hours
// from this cache for up to the TTL below. Pinned by
// `test/features/schedule/presentation/
// salon_effective_schedule_cross_session_isolation_test.dart`.

// `KeepAliveLink` is not part of `riverpod_annotation`'s show-list — it lives
// on the dedicated advanced-API surface, `misc.dart` (mirrors
// `package:riverpod/misc.dart`; imported via `flutter_riverpod`, an existing
// direct dependency, rather than adding `riverpod` itself as one). Same
// reasoning, same spelling, as `bookings_day_notifier.dart`'s own import.
import 'package:flutter_riverpod/misc.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/schedule_repository.dart';
import '../data/schedule_repository_provider.dart';
import '../domain/weekly_schedule.dart';
import 'salon_schedule_keep_alive_lru.dart';
import 'schedule_range.dart';

part 'salon_effective_schedule_notifier.g.dart';

/// How long a successfully-fetched `(salonId, range)` window stays pinned in
/// memory after nothing watches it. Same 5 minutes, and the same reasoning, as
/// `effective_schedule_notifier.dart`'s `_kRangeCacheTtl`.
const Duration _kSalonRangeCacheTtl = Duration(minutes: 5);

/// Resolves EVERY active master's effective schedule across [range], keyed by
/// master id — see [SalonRosterScheduleRepository.salonRosterEffectiveSchedule]
/// for the roster-completeness guarantee that makes "off today" distinguishable
/// from "not loaded".
///
/// Generated provider name: `salonEffectiveScheduleProvider` (a family — call
/// `salonEffectiveScheduleProvider(salonId, range)`).
@riverpod
class SalonEffectiveScheduleNotifier extends _$SalonEffectiveScheduleNotifier {
  @override
  Future<Map<String, List<EffectiveDay>>> build(
    String salonId,
    ScheduleRange range,
  ) async {
    // `range` is date-only by construction (see [ScheduleRange]), so the family
    // key already equals the fetched window — no late normalisation needed.
    final Map<String, List<EffectiveDay>> byMaster = await ref
        .watch(salonRosterScheduleRepositoryProvider)
        .salonRosterEffectiveSchedule(salonId, range.from, range.to);

    // SUCCESS path only — reached only after the await resolved. Opens one
    // [KeepAliveLink], starts one [Timer] that closes it after the TTL, and
    // registers [Ref.onDispose] to cancel that [Timer] so a superseded build
    // can never leave a pending timer behind.
    //
    // ╔═════════════════════════════════════════════════════════════════════╗
    // ║ THE MEMBER BUDGET — SHIPPED 2026-09-20, AHEAD OF THE `onDayChanged` ║
    // ║ RE-KEY IT EXISTS FOR.                                               ║
    // ║                                                                     ║
    // ║ This block used to be a boxed REQUIREMENT asking the next author to ║
    // ║ ship a budget IN THE SAME CHANGE as that re-key, because the pin     ║
    // ║ below was unbounded and only safe by accident of the current key:    ║
    // ║ the board's single watch site (`salon_bookings_screen.dart:351`)     ║
    // ║ passes `ScheduleRange.month(kyivToday(clock))` — TODAY's month, NOT  ║
    // ║ the selected day's — so exactly ONE member exists per salon per      ║
    // ║ session however the owner pages (measured: 1 fetch across 21 day     ║
    // ║ taps and 6 week pages, 2026-09-17). A re-key on the SELECTED month   ║
    // ║ turns that into one member PER MONTH REACHED: ±180 days of rail →    ║
    // ║ ~12 concurrent members, each pinned 5 minutes with nothing evicting  ║
    // ║ them, ~3,700 live [EffectiveDay] objects at a roster of 10. Riverpod ║
    // ║ autoDispose cannot help — the `keepAlive()` link is what defeats it. ║
    // ║                                                                     ║
    // ║ A requirement written in a comment is a guard made of attention, so  ║
    // ║ it was replaced by the real thing: [SalonScheduleKeepAliveLru], a    ║
    // ║ bounded LRU of [KeepAliveLink]s keyed exactly as this family is      ║
    // ║ (`salon_schedule_keep_alive_lru.dart` — modelled on                  ║
    // ║ `bookings_day_notifier.dart`'s `DayKeepAliveLru`, and that file      ║
    // ║ states why that class could not simply be reused). At today's key it ║
    // ║ never evicts anything and changes NO behaviour; the day the key      ║
    // ║ widens, the bound is already in place.                               ║
    // ╚═════════════════════════════════════════════════════════════════════╝
    final KeepAliveLink link = ref.keepAlive();
    final SalonScheduleKey key = (salonId, range);
    // CAPTURED into a local BEFORE `onDispose`, never read from inside it.
    // Riverpod 3 asserts `_debugCallbackStack == 0` in `Ref.read`, so a
    // `ref.read(...)` inside a life-cycle callback throws "Cannot use Ref or
    // modify other providers inside life-cycles/selectors" — and it throws
    // from `AuthNotifier.logout`'s own invalidate, which is where the
    // disposal actually runs. Caught by
    // `test/core/provider_cycle_guard_test.dart`'s logout entrypoint on the
    // first run of this code. The LRU is `keepAlive: true` and
    // container-scoped, so a captured reference is valid for this element's
    // whole life.
    final SalonScheduleKeepAliveLru lru = ref.read(
      salonScheduleKeepAliveLruProvider,
    );
    // The LRU owns the TTL timer now — it has to, or an eviction would close
    // the link while a stray timer still pointed at the slot. `onDispose`
    // FORGETS (cancels the timer, drops the entry) rather than closing: by
    // then the element's keepAlive links are already gone.
    lru.touch(key, link, _kSalonRangeCacheTtl);
    ref.onDispose(() => lru.forget(key));

    return byMaster;
  }
}
