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
// There is deliberately NO member budget (no LRU) on the family. That is safe
// ONLY because of today's key — and the named `onDayChanged` follow-up would
// invalidate that reasoning. See the boxed REQUIREMENT at the `ref.keepAlive()`
// call below BEFORE re-keying this on the selected month.
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

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/schedule_repository.dart';
import '../data/schedule_repository_provider.dart';
import '../domain/weekly_schedule.dart';
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
    // ║ ⛔ STOP — READ THIS BEFORE WIRING `onDayChanged`.                   ║
    // ║                                                                     ║
    // ║ THERE IS NO MEMBER BUDGET ON THIS FAMILY, AND THAT IS ONLY SAFE     ║
    // ║ BECAUSE OF THE CURRENT KEY. The board's single watch site            ║
    // ║ (`salon_bookings_screen.dart:351`) passes                            ║
    // ║ `ScheduleRange.month(kyivToday(clock))` — TODAY's month, NOT the     ║
    // ║ selected day's. So exactly ONE member exists per salon per session   ║
    // ║ no matter how the owner pages (mobile-perf measured 1 fetch across   ║
    // ║ 21 day taps and 6 week pages, 2026-09-17), and an unbounded pin of   ║
    // ║ "one" needs no eviction policy.                                      ║
    // ║                                                                     ║
    // ║ THE NAMED FOLLOW-UP BREAKS THAT PRECONDITION. Re-keying this on the  ║
    // ║ SELECTED month (the additive `onDayChanged` seam that                ║
    // ║ `salon_bookings_screen.dart`'s "⚠ THE MONTH IS KYIV-TODAY'S"        ║
    // ║ section describes) turns one member into one PER MONTH REACHED. The  ║
    // ║ rail spans ±180 days → ~12 concurrent members, each pinned 5 minutes ║
    // ║ by the `keepAlive` below with NOTHING evicting them: at a roster of  ║
    // ║ 10 that is ~3,700 live [EffectiveDay] objects held past the last     ║
    // ║ look. Riverpod's autoDispose cannot help — the `keepAlive()` link is ║
    // ║ precisely what defeats it.                                           ║
    // ║                                                                     ║
    // ║ REQUIREMENT (mobile-perf LOW, 2026-09-17): a bounded member budget   ║
    // ║ MUST SHIP IN THE SAME CHANGE AS THE `onDayChanged` RE-KEY — not as a ║
    // ║ follow-up to the follow-up. Model it on                              ║
    // ║ `bookings_day_notifier.dart`'s `DayKeepAliveLru` (`_kMaxKeptDays`):  ║
    // ║ a small LRU of [KeepAliveLink]s keyed the same way this family is,   ║
    // ║ closing the least-recently-touched link once the budget is exceeded, ║
    // ║ swept at the session boundary by `AuthNotifier.logout` alongside the ║
    // ║ bare invalidate it already performs on this family. A reviewer who   ║
    // ║ sees an `onDayChanged`-keyed range arrive here WITHOUT such a budget ║
    // ║ should treat it as an incomplete change and send it back.            ║
    // ╚═════════════════════════════════════════════════════════════════════╝
    final link = ref.keepAlive();
    final Timer timer = Timer(_kSalonRangeCacheTtl, link.close);
    ref.onDispose(timer.cancel);

    return byMaster;
  }
}
