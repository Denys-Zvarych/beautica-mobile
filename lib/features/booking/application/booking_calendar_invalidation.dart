// 2026-07-26 booking-conflict design — the ONE cross-feature fan-out point
// for "an EXTERNAL write silently changed one or more bookings' statuses".
//
// Currently the only such write is `OverridesNotifier.putOverride(...,
// cancelOverlapping: true)` (`lib/features/schedule/presentation/
// overrides_notifier.dart`), called from `DayHoursSheet` after the master
// confirms `DayOffConflictDialog`: the backend declines every conflicting
// CONFIRMED booking atomically with the schedule write, but nothing in the
// `schedule` feature's own provider graph knows those bookings exist —
// `OverridesNotifier` only reloads its own override range.
//
// Deliberately its OWN file (mirrors `services/presentation/
// service_catalogue_invalidation.dart`'s "one fan-out point" precedent),
// exposed for a CROSS-feature caller rather than that file's same-feature
// one: the booking feature is the only place that knows which of its own
// caches need to drop when a booking's status changes underneath it, so it
// owns this policy rather than making `schedule` reach in and enumerate
// booking provider names directly. `schedule/presentation/day_hours_sheet
// .dart` imports ONLY this function — the narrowest cross-feature surface
// that satisfies the "invalidate the bookings/calendar providers" contract.
//
// Top-level function taking a `WidgetRef`, not a notifier method: it must be
// callable from `DayHoursSheet` (a widget, not a Notifier) after the write
// settles, and — mirroring `service_catalogue_invalidation.dart`'s own
// rationale — a cross-provider `ref.invalidate` belongs outside any Notifier
// body so `scripts/forbid_provider_self_invalidation.sh` never has to special-
// case it.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';

import '../domain/booking_tab.dart';
import '../domain/bookings_day_query.dart';
import 'booked_days_notifier.dart';
import 'booking_detail_notifier.dart';
import 'bookings_day_notifier.dart';
import 'master_archive_notifier.dart';
import 'my_bookings_notifier.dart';

/// Invalidates every cached master-facing booking view after an external
/// write declined [declinedBookingIds], scoped to the calendar days
/// [affectedDates] actually touched.
///
///   • [bookingDetailProvider] — one invalidation per id (autoDispose family;
///     a no-op for any id nobody is currently viewing).
///   • [bookingsDayProvider] — ONE invalidation per DISTINCT date in
///     [affectedDates] (mobile-perf MEDIUM, 2026-07-26 fix), not the whole
///     family. The whole-family invalidation this replaced refetched every
///     day currently cached — including days this write never touched — and
///     evicted the bounded 3-day keepAlive LRU
///     (`bookings_day_notifier.dart`'s `_kMaxKeptDays`) for nothing,
///     defeating its "settled revisit costs nothing" guarantee. Each caller
///     already knows exactly which dates changed (e.g. every
///     `OverrideConflict.date` from the conflict check that authorised the
///     write), so there is no need to guess at the whole family.
///
///     TWO members per date, not one — and that is a correctness
///     requirement, not belt-and-braces (mobile-perf HIGH, 2026-08-13):
///
///       – `BookingsDayQuery.dayList(day: d)` — the DEFAULT day-list member
///         (`{CONFIRMED, COMPLETED, NOT_COMPLETED}` on the wire). This is the
///         one `BookingsDiscoveryView` actually watches on an untouched
///         «Мої записи», so it is the one that MUST drop. It did not exist
///         when this function was written; when the day list started hiding
///         CANCELLED/DECLINED by default (locked 2026-08-13) the screen moved
///         to a new family key and this site kept invalidating the old one,
///         so a decline through `DayHoursSheet` left the master's own list
///         serving the declined booking as CONFIRMED — pinned across screen
///         disposal by `bookings_day_notifier.dart`'s ≤3-day keepAlive LRU,
///         recoverable only by a manual pull-to-refresh. Built through the
///         shared factory so this can never drift from the screen again.
///       – `BookingsDayQuery.of(day: d)` — the PLAIN, empty-status member.
///         No other `lib/` host reads it today (checked, mobile-perf
///         2026-08-13); it is load-bearing because the DAY LIST ITSELF
///         resolves to this key once the master ticks every filter group —
///         `BookingStatus.dayListWireStatuses` maps the maximal selection to
///         `const <BookingStatus>{}`, i.e. no `status` param at all, which is
///         exactly this member. Dropping this call would leave the
///         select-all view stale.
///
///     Invalidating a family member with no live listener is a documented
///     no-op, so the second call costs nothing whenever only one is mounted.
///
///     LIMITATION, accepted: a member carrying a MASTER-CHOSEN filter — the
///     list narrowed to «Скасовані», or to one service — is a third family
///     key and is not caught here; it goes stale until its own keepAlive
///     window elapses or it is next rebuilt naturally. That is a stale
///     filtered view behind a visible funnel badge, on a screen the master
///     deliberately narrowed, so it is not worth widening this to every
///     filter combination that has ever touched [affectedDates]. The two
///     members above are the ones a master lands on without choosing
///     anything, which is why they are not part of that trade.
///   • [myBookingsProvider] `upcoming` + `cancelled` tabs — a DECLINED
///     booking leaves `upcoming` and enters `cancelled`; same two tabs
///     `BookingDetailScreen` invalidates after its own decline. These two
///     stay whole-family-by-tab (not per-date) — they are already scoped to
///     exactly two members, not a whole family sized by every day ever
///     visited.
///   • [nextAppointmentProvider] (Phase 225) — the CLIENT Home Hub's own
///     «Найближчий запис» card. A declined booking may have BEEN the
///     client's soonest upcoming appointment, so this must refresh alongside
///     `upcoming`/`cancelled` above. No cycle risk: `nextAppointmentProvider`
///     only watches `bookingRepositoryProvider` (the data layer) — it never
///     watches anything in this file or anything that watches back to it —
///     so invalidating it here cannot loop back into this function.
///   • [bookedDaysProvider] — the day-rail's and month panel's dot set
///     (2026-08-20 fix, matching [invalidateBookingViewsAfterBookingCreated]'s
///     own). This site's ONLY transition is CONFIRMED → DECLINED (the backend
///     declines every conflicting booking atomically with the day-off write),
///     and that CROSSES the rail query's allow-list boundary:
///     `BookingRepository#findBookedDatesByMasterId`
///     (`BookingRepository.java:175-195`) allow-lists
///     `CONFIRMED / COMPLETED / NOT_COMPLETED`, so a decline can take the
///     LAST dotted booking off a day and the dot must go with it — otherwise
///     the rail points at a day whose list now renders empty, which that
///     query's own header calls "a user-visible lie". Nothing else here drops
///     it: it is a filter-independent `keepAlive()` SINGLETON with a
///     thirty-minute TTL (`booked_days_notifier.dart`), not a member of the
///     [bookingsDayProvider] family invalidated above, so without this call
///     the stale dot survives for up to half an hour and across screen
///     disposal.
///
/// Cost: one refetch per LIVE subscriber (Riverpod drops an invalidated
/// `autoDispose`/`keepAlive` provider with no listeners instead of refetching
/// eagerly), so calling this while none of these screens are on-screen costs
/// nothing.
///
/// The consequence for callers — the SAME contract all three helpers in this
/// file carry: this guarantees the caches are DROPPED, never that they have
/// been REFILLED by the time it returns. A covered consumer's subscription is
/// paused (Riverpod 3), so the queued refresh may be dropped and the refetch
/// land only on resume. Anything that needs the new data in hand must read the
/// provider itself. See [invalidateBookingViewsAfterBookingCreated]'s doc for
/// the full mechanism.
void invalidateBookingViewsAfterExternalDecline(
  WidgetRef ref,
  Iterable<String> declinedBookingIds, {
  required Iterable<DateTime> affectedDates,
}) {
  for (final String id in declinedBookingIds) {
    ref.invalidate(bookingDetailProvider(id));
  }
  // FIX B mirror (mobile-debugger, this track — found via
  // `scripts/forbid_bare_keepalive_family_invalidation.sh`, not in the
  // original named item list, fixed with the identical idiom rather than
  // allow-listed away: this site is structurally the SAME
  // `ProviderSubscription`-closed precondition as
  // [invalidateBookingViewsAfterProviderClose]'s FIX B — per-date-SCOPED
  // already protects it from the "every other cached day" blast radius, but
  // scoping alone never closed the disposal race; only the wasPinned gate
  // does).
  final DayKeepAliveLru lru = ref.read(dayKeepAliveLruProvider);
  for (final DateTime day in affectedDates.toSet()) {
    // BOTH members — see the doc above. `.dayList` is the one the master's own
    // «Мої записи» watches by default; `.of` is the plain one other hosts use.
    for (final BookingsDayQuery affectedQuery in <BookingsDayQuery>[
      BookingsDayQuery.dayList(day: day),
      BookingsDayQuery.of(day: day),
    ]) {
      final bool wasPinned = lru.contains(affectedQuery);
      ref.invalidate(bookingsDayProvider(affectedQuery));
      if (wasPinned) {
        ref.read(bookingsDayProvider(affectedQuery));
      }
    }
  }
  ref.invalidate(myBookingsProvider(BookingTab.upcoming));
  ref.invalidate(myBookingsProvider(BookingTab.cancelled));
  ref.invalidate(nextAppointmentProvider);
  ref.invalidate(bookedDaysProvider);
}

/// Invalidates every master-facing booking cache a PROVIDER-INITIATED close
/// (decline or complete) of [bookingId] must drop, regardless of which
/// screen performed the write.
///
/// 2026-08-16 bug this fixes: `BookingDetailScreen._confirmDecline`/
/// `._confirmComplete` invalidated `bookingDetailProvider`+`bookingsDayProvider`
/// by hand and never `masterArchiveProvider`; separately,
/// `MasterArchiveScreen._confirmComplete` invalidated `masterArchiveProvider`+
/// `bookingsDayProvider` by hand and never worried about `bookingDetailProvider`.
/// Two independent hand-rolled fan-outs implementing the same "a booking's
/// status just closed" contract is exactly how one of them silently missed a
/// target — a master who declined/completed a booking they opened FROM the
/// archive (`master_archive_screen.dart:248-250` pushes the SAME
/// `BookingDetailScreen` every other entry point does) saw the archive list
/// keep serving the stale pre-close row until its own eventual, unrelated
/// refetch. ONE fan-out point (mirrors
/// [invalidateBookingViewsAfterExternalDecline]'s "one fan-out point"
/// precedent above) so `booking_detail_screen.dart` and
/// `master_archive_screen.dart` cannot independently drift on this again —
/// every future call site of either wires through here.
///
///   • [bookingDetailProvider] — this one [bookingId] (autoDispose family; a
///     no-op for any id nobody is currently viewing — including a call from
///     the archive screen, which never has this booking's detail warm to
///     begin with, so this is free there, not merely harmless).
///   • [bookingsDayProvider] — scoped to [affectedDate] (the booking's own
///     `startAt`, Kyiv-classified via `kyivDayOf` by the caller), BOTH family
///     members (`.dayList` + `.of`, same "TWO members" reasoning as
///     [invalidateBookingViewsAfterExternalDecline]'s doc), each gated on
///     [DayKeepAliveLru.contains] with an eager `ref.read` back when pinned —
///     the EXACT idiom
///     [invalidateBookingsDayAfterAppointmentItemReschedule] below uses, and
///     for the identical reason.
///
///     FIX B (mobile-debugger, this track) — the SAME `ProviderSubscription`-
///     closed crash [invalidateBookingsDayAfterAppointmentItemReschedule]'s
///     "FIX A" fixes, reachable through THIS helper instead: view day X → view
///     day Y (X is now pinned-but-unwatched via the bounded keepAlive LRU,
///     zero listeners) → open a booking on Y → decline/complete it (this
///     helper's old bare-family `ref.invalidate(bookingsDayProvider)` ran
///     `invalidateSelf()` on EVERY existing family member, including X) →
///     rail-tap back to X. If the scheduler's queued disposal for X's element
///     fired at (or interleaved with) the moment the rail's `ref.watch`
///     re-subscribed, the watcher observed an element mid-teardown and threw.
///     A bare family invalidate used to be safe-by-cost-accounting here (see
///     the paragraph FIX A's doc structure replaces) but was never safe
///     against THIS race — the race does not care how many members get
///     invalidated, only whether any zero-listener, keepAlive-pinned one does.
///     Scoping to [affectedDate] the way [invalidateBookingViewsAfterExternalDecline]
///     already does removes the "every other cached day" blast radius for
///     free, and the `wasPinned`-gated eager read is what actually closes the
///     race for the ONE day this write really did affect.
///   • [masterArchiveProvider] — the BARE family (every filter combination a
///     master may have applied) — the fix. `MasterArchiveNotifier` is
///     `autoDispose` per filter combination (its own file header), so this is
///     a no-op for any combination the master isn't currently viewing.
///   • [bookedDaysProvider] — the day-rail's and month panel's dot set
///     (2026-08-20 fix). Added for the DECLINE arm specifically, and only
///     after checking each arm against the rail query's allow-list
///     (`BookingRepository#findBookedDatesByMasterId`,
///     `BookingRepository.java:175-195`, allow-lists
///     `CONFIRMED / COMPLETED / NOT_COMPLETED`):
///
///       – DECLINE (`BookingDetailScreen._confirmDecline`) — CONFIRMED →
///         DECLINED. CROSSES the boundary: the booking leaves the allow-list,
///         so if it was the day's last one the dot must go. This is the whole
///         reason the call is here.
///       – COMPLETE (`BookingDetailScreen._confirmComplete`,
///         `MasterArchiveScreen._confirmComplete`) — CONFIRMED → COMPLETED.
///         BOTH statuses are allow-listed, so the day's dot set is
///         mathematically unchanged and this invalidation is redundant on
///         those two paths. It is kept anyway rather than being pushed down
///         into the decline call site: the whole point of this file is that
///         "which caches does a status close drop?" has ONE answer per
///         helper, and re-splitting it per transition is exactly the
///         hand-rolled-fan-out drift the 2026-08-16 archive-staleness bug
///         came from. The redundant cost is bounded and small — ONE extra
///         refetch of a singleton, and only while «Мої записи» is actually
///         mounted (a no-op otherwise), on a user-initiated confirm-dialog
///         action, not a scroll or a rebuild.
///
///     Nothing else here would drop it: it is a filter-independent
///     `keepAlive()` SINGLETON with a thirty-minute TTL
///     (`booked_days_notifier.dart`), not a member of the
///     [bookingsDayProvider] family invalidated above.
///
/// Cost: one refetch per LIVE subscriber, same accounting as
/// [invalidateBookingViewsAfterExternalDecline] — calling this while none of
/// these screens are on-screen costs nothing.
///
/// The consequence for callers — the SAME contract all three helpers in this
/// file carry: this guarantees the caches are DROPPED, never that they have
/// been REFILLED by the time it returns. Anything that needs the new data in
/// hand must read the provider itself. See
/// [invalidateBookingViewsAfterBookingCreated]'s doc for the full mechanism.
void invalidateBookingViewsAfterProviderClose(
  WidgetRef ref,
  String bookingId, {
  required DateTime affectedDate,
}) {
  ref.invalidate(bookingDetailProvider(bookingId));

  // FIX B — see the doc above. Same gated idiom as
  // [invalidateBookingsDayAfterAppointmentItemReschedule]: only a query this
  // session has actually built (and is therefore at risk of the disposal
  // race) pays for the eager read-back; an untouched query is a genuine no-op
  // either way.
  final DayKeepAliveLru lru = ref.read(dayKeepAliveLruProvider);
  for (final BookingsDayQuery affectedQuery in <BookingsDayQuery>[
    BookingsDayQuery.dayList(day: affectedDate),
    BookingsDayQuery.of(day: affectedDate),
  ]) {
    final bool wasPinned = lru.contains(affectedQuery);
    ref.invalidate(bookingsDayProvider(affectedQuery));
    if (wasPinned) {
      ref.read(bookingsDayProvider(affectedQuery));
    }
  }

  ref.invalidate(masterArchiveProvider);
  ref.invalidate(bookedDaysProvider);
}

/// Invalidates every master-facing booking cache the CREATION of a booking on
/// the master's own calendar must drop.
///
/// Takes a provider-side [Ref], not a [WidgetRef], because its caller is a
/// Notifier (`MasterCreateBookingNotifier.submit`) rather than a widget — the
/// two `WidgetRef` helpers above are called from widgets after a write
/// settles. That is the ONLY difference; this exists in the same file for the
/// same reason they do: so "which caches does a booking write drop?" has one
/// answer, in the feature that owns those caches, instead of being re-derived
/// inline at each call site (see this file's header).
///
///   • [bookingsDayProvider] — every currently-built family member (this
///     helper's caller does not know which day the master's «Мої записи» is
///     currently viewing), reached by enumerating [DayKeepAliveLru
///     .liveQueries] rather than a bare `ref.invalidate(bookingsDayProvider)`
///     — see "FIX (mobile-debugger, this track)" below for why the bare form
///     was unsafe and why enumerating is scope-IDENTICAL to it, not
///     narrower: [DayKeepAliveLru.touch] runs unconditionally on every
///     [BookingsDayNotifier.build] regardless of listener state, so every
///     member that currently exists — watched or pinned-but-unwatched — is
///     tracked there, and nothing outside that bounded ≤3-day set can exist
///     (an evicted query's [KeepAliveLink] closing is what lets Riverpod
///     dispose it in the first place). Every other cached day (i.e. every day
///     NOT in that bounded set) was already disposed before this call runs,
///     so there is nothing further for this helper to reach.
///
///     ## FIX (mobile-debugger, this track) — the MISSED site
///
///     This function used to read `ref.invalidate(bookingsDayProvider);` —
///     no query argument, the family's OWN bare invalidate. That was
///     allow-listed (`scripts/.keepalive_family_invalidation_allow`) rather
///     than fixed, on the reasoning that its one caller
///     (`MasterCreateBookingNotifier.submit`) always fires while the
///     day-calendar screen is COVERED by the full-screen «Новий запис»
///     wizard, and Riverpod 3 PAUSES a covered consumer instead of dropping
///     its listener to zero. That reasoning is true ONLY for the ONE day the
///     rail happens to be showing at submit time. It is FALSE for every
///     OTHER day still sitting in [DayKeepAliveLru] — a day the master
///     glanced at earlier this session, then scrubbed the rail away from,
///     which is pinned via a [KeepAliveLink] with genuinely ZERO listeners,
///     not merely paused. A bare family invalidate calls `invalidateSelf()`
///     on THAT element too, which is the EXACT `ProviderSubscription`-closed
///     precondition [invalidateBookingsDayAfterAppointmentItemReschedule]'s
///     "FIX A" doc (below) and [invalidateBookingViewsAfterProviderClose]'s
///     "FIX B" doc already fixed at their own sites — this function was the
///     one place that class of bug survived the original sweep, because its
///     caller shape ("always covered") looked safe for the single watched
///     member and nobody separately checked the OTHER, merely-pinned ones.
///
///     Fixed with the IDENTICAL idiom every other site in this file uses:
///     gate each candidate on [DayKeepAliveLru.contains] (trivially `true`
///     for every member [liveQueries] itself just enumerated, but checked
///     the same way regardless, so this stays visually and structurally
///     identical to the other three sites — no second mechanism to audit),
///     `ref.invalidate`, then an eager `ref.read` back to re-touch the
///     keepAlive link before the scheduler's queued disposal task can fire.
///     At most 3 extra eager reads (`bookings_day_notifier.dart`'s
///     `_kMaxKeptDays`), bounded by the same cap that already bounds this
///     LRU everywhere else.
///   • [bookedDaysProvider] — THE FIX (mobile-debugger MEDIUM, 2026-08-20).
///     The day-rail's and month panel's dot set. A brand-new booking on a day
///     that had none is precisely a change to a booking's EXISTENCE, which is
///     the condition `booked_days_notifier.dart`'s own header names as
///     requiring an explicit invalidation — and that provider is a
///     `keepAlive()` singleton with a THIRTY-MINUTE TTL, so without this the
///     day the master just booked stayed undotted for up to half an hour on
///     both the rail and the month grid. Nothing else would have dropped it:
///     it is filter-independent, so it is not a member of any family the day
///     list invalidates.
///
/// Cost: one refetch per LIVE subscriber, same accounting as the two helpers
/// above, PLUS at most 3 eager reads for pinned-but-unwatched members (the
/// FIX above) — calling this while «Мої записи» is not on screen costs
/// nothing.
///
/// **When the refetch actually happens.** Two different members, two
/// different answers:
///
///   - The ONE day the rail happens to be showing at submit time: the wizard
///     is a full-screen route, so in practice that day's `Consumer` is
///     COVERED for the whole submit, and Riverpod 3 pauses a covered
///     consumer's subscriptions. A paused listener does not make an element
///     active (`element.dart`: `isActive => (listenerCount -
///     pausedActiveSubscriptionCount) > 0`), and the scheduler only flushes
///     active elements (`scheduler.dart::_performRefresh`) before clearing
///     its queue unconditionally — so the refresh this call queues for THAT
///     member is DROPPED rather than run while the wizard is on top. That is
///     not a leak: `invalidateSelf()` has already severed the element's
///     `KeepAliveLink`s and left `_mustRecomputeState = true`, so the member
///     is recomputed by the first READ after the wizard pops.
///   - Every OTHER member [DayKeepAliveLru.liveQueries] enumerates (pinned
///     but genuinely zero-listener): the FIX's eager `ref.read` forces a
///     SYNCHRONOUS refetch right here, before this function returns — the
///     same "genuine eager refetch, not a workaround" contract
///     [invalidateBookingsDayAfterAppointmentItemReschedule]'s own doc
///     describes, for the identical reason (re-touching the keepAlive link
///     is what cancels the queued disposal).
///
/// The consequence for callers: this helper guarantees the caches are
/// DROPPED, and the pinned-but-unwatched ones are additionally REFILLED
/// before it returns — but the one actively-covered member is not
/// guaranteed refilled by the time it returns. Anything that needs the new
/// data in hand must read the provider itself. See
/// `bookings_day_notifier.dart`'s header ("What the queued refresh does and
/// does NOT guarantee") for the full mechanism.
///
/// Cycle-safe: neither target watches, even transitively,
/// `masterCreateBookingProvider`, so this closes no back-edge.
void invalidateBookingViewsAfterBookingCreated(Ref ref) {
  final DayKeepAliveLru lru = ref.read(dayKeepAliveLruProvider);
  for (final BookingsDayQuery query in lru.liveQueries) {
    final bool wasPinned = lru.contains(query);
    ref.invalidate(bookingsDayProvider(query));
    if (wasPinned) {
      ref.read(bookingsDayProvider(query));
    }
  }
  ref.invalidate(bookedDaysProvider);
}

/// Drops the master's own «Мої записи» day-calendar cache for
/// [affectedDays] after a per-item VISIT reschedule
/// (`booking_confirm_screen.dart`'s `rescheduleAppointmentId != null`
/// branch) — the NEW day the item moved to and, if resolvable, the OLD day
/// it moved from.
///
/// Extracted into its own named, independently-testable function (rather
/// than left inline at its one call site) for two reasons: it is the ONE
/// place a PER-ITEM VISIT reschedule's calendar fan-out is decided, mirroring
/// this file's other helpers; and FIX A below needs a regression test that
/// exercises the EXACT production invalidation, not a hand-copied
/// approximation of it that could quietly drift from the real thing.
///
///   • [bookingsDayProvider] — BOTH day-list family members per affected
///     date — see [invalidateBookingViewsAfterExternalDecline]'s doc for why
///     `.dayList` (what `BookingsDiscoveryView` actually watches) and `.of`
///     (what the SAME screen resolves to once every filter is ticked) are
///     both required, not belt-and-braces. Invalidating a family member with
///     no live listener, and that was never built this session, is a
///     documented no-op — safe to call unconditionally even for a CLIENT
///     viewer who has no day-calendar screen.
///   • [bookedDaysProvider] — the day-rail's and month panel's dot set
///     (mobile-debugger fix, this track, matching
///     [invalidateBookingViewsAfterBookingCreated]'s own 2026-08-20 fix,
///     which this helper had missed). A per-item VISIT reschedule moves a
///     booking's `startAt` onto the NEW day in [affectedDays] and, for the
///     OLD day it moved off of, changes that day's booking membership too —
///     exactly the "a booking's EXISTENCE at a date changed" trigger
///     `booked_days_notifier.dart`'s own header names as requiring an
///     explicit invalidation. It is a filter-independent `keepAlive()`
///     SINGLETON with a thirty-minute TTL, not a member of the
///     [bookingsDayProvider] family invalidated above, so without this call
///     a day whose ONLY booking just moved onto (or off of) it kept showing
///     its stale dot state — undotted, or wrongly still dotted — for up to
///     half an hour: this is the "day rail shows no dot when the day has
///     only 1 booking and it's a manual [walk-in] booking" bug. No
///     `wasPinned` gating needed for this one call (unlike the family
///     members above): it is a singleton, not a keyed family member with
///     pinned-but-unwatched elements, so it is not subject to FIX A's
///     disposal race below — a bare `ref.invalidate` is correct here, exactly
///     as in this file's other three helpers.
///
/// ## FIX A (mobile-debugger, this session) — the crash this fixes
///
/// **Symptom**: after rescheduling a walk-in to a day with no other
/// bookings, opening that day sometimes threw "Bad state:
/// ProviderSubscription.read on a subscription that was closed" inside
/// `bookings_discovery_view.dart`'s `Consumer`; more often the SAME throw was
/// silently absorbed by Flutter's per-`Element` error boundary, leaving the
/// day's skeleton stuck forever (one mechanism, two visible symptoms).
///
/// **Mechanism** (verified against `package:riverpod` 3.1.0's own
/// `element.dart`/`scheduler.dart` — the version this repo's `pubspec.lock`
/// pins): a bare `ref.invalidate(bookingsDayProvider(q))` on a query
/// [DayKeepAliveLru] pins ONLY via its bounded keepAlive (the master glanced
/// at that day earlier this session, then scrubbed the rail away —
/// "pinned-but-unwatched") calls `invalidateSelf()`, which unconditionally
/// `runOnDispose()`s FIRST — nulling the element's own keepAlive-link
/// reference — THEN calls `mayNeedDispose()`, which (finding zero listeners
/// AND, because of the reference it just cleared, zero links)
/// unconditionally queues the element for disposal via the scheduler. That
/// queued disposal races whatever widget rebuild next `ref.watch`es the SAME
/// query (a rail re-tap, a pop) — if the scheduler's task fires first, or
/// interleaves mid-rebuild, the watcher's fresh subscription can observe an
/// element mid-teardown and throw.
///
/// **Fix**: `ProviderScheduler._performDispose` RE-CHECKS the element's
/// keepAlive links at TASK-FIRE time, not at schedule time — so
/// re-establishing a link SYNCHRONOUSLY, before that task ever runs,
/// reliably cancels the disposal already queued against it.
/// `ref.read(bookingsDayProvider(q))` right after the invalidate does exactly
/// that: `container.read` creates a THROWAWAY subscription (`listen` →
/// `readSafe` → `close`), and `readSafe` calls `element.flush()`, which —
/// because `invalidateSelf` left `_mustRecomputeState = true` — synchronously
/// re-runs `build()`, which re-touches [DayKeepAliveLru] (a fresh
/// `ref.keepAlive()` link) BEFORE the throwaway subscription's own `close()`
/// (and long before the scheduler's queued task) ever gets a chance to
/// dispose it. This is a genuine EAGER refetch, not a workaround that merely
/// dodges the crash by doing less — it cannot silently swallow the refresh
/// the way a dropped queued-refresh legitimately can for a COVERED-but-
/// still-watched consumer (contrast [invalidateBookingViewsAfterExternalDecline]'s
/// documented "drop is fine, the next read recomputes" contract — a
/// DIFFERENT, non-crashing path: an actively-watched, merely-paused element
/// never hits the zero-listener disposal branch at all).
///
/// Gated on [DayKeepAliveLru.contains] so a query nobody has ever built this
/// session (a CLIENT rescheduling their own booking, or a master who never
/// opened the day-calendar) keeps costing exactly nothing; only a query that
/// genuinely IS pinned — and therefore genuinely at risk of this race —
/// pays for the eager read.
void invalidateBookingsDayAfterAppointmentItemReschedule(
  WidgetRef ref, {
  required Set<DateTime> affectedDays,
}) {
  final DayKeepAliveLru lru = ref.read(dayKeepAliveLruProvider);
  for (final DateTime day in affectedDays) {
    for (final BookingsDayQuery affectedQuery in <BookingsDayQuery>[
      BookingsDayQuery.dayList(day: day),
      BookingsDayQuery.of(day: day),
    ]) {
      final bool wasPinned = lru.contains(affectedQuery);
      ref.invalidate(bookingsDayProvider(affectedQuery));
      if (wasPinned) {
        ref.read(bookingsDayProvider(affectedQuery));
      }
    }
  }
  ref.invalidate(bookedDaysProvider);
}
