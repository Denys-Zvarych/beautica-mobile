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
  for (final DateTime day in affectedDates.toSet()) {
    // BOTH members — see the doc above. `.dayList` is the one the master's own
    // «Мої записи» watches by default; `.of` is the plain one other hosts use.
    ref.invalidate(bookingsDayProvider(BookingsDayQuery.dayList(day: day)));
    ref.invalidate(bookingsDayProvider(BookingsDayQuery.of(day: day)));
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
///   • [bookingsDayProvider] — the BARE family (no query argument), not a
///     per-date target: unlike [invalidateBookingViewsAfterExternalDecline]
///     (whose caller always knows every affected date from its own
///     conflict-check response), a manual decline/complete from the detail
///     screen or the archive is always exactly ONE booking with no separate
///     "which calendar day(s) changed" signal reaching this helper — the
///     booking's own `startAt` is available at both call sites, but deriving
///     "the affected date" from it would still be one date, and passing the
///     bare family costs nothing extra: Riverpod only EAGERLY recomputes the
///     family members that currently have an active listener (at most the
///     bounded ≤3-day keepAlive LRU's worth, `bookings_day_notifier.dart`'s
///     `_kMaxKeptDays`); every other cached day refetches lazily the next
///     time it's watched. Same reasoning `BookingDetailScreen` documented at
///     its own former call site before this helper existed.
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
void invalidateBookingViewsAfterProviderClose(WidgetRef ref, String bookingId) {
  ref.invalidate(bookingDetailProvider(bookingId));
  ref.invalidate(bookingsDayProvider);
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
///   • [bookingsDayProvider] — the BARE family. Same reasoning as
///     [invalidateBookingViewsAfterProviderClose]'s: this helper's caller does
///     not know which day the master's «Мої записи» is currently viewing, and
///     Riverpod only EAGERLY recomputes the members with an active listener
///     (at most the bounded ≤3-day keepAlive LRU) — every other cached day
///     refetches lazily when next watched.
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
/// above — calling this while «Мої записи» is not on screen costs nothing.
/// **When the refetch actually happens.** The wizard is a full-screen route,
/// so in practice the day list underneath it is COVERED for the whole submit,
/// and Riverpod 3 pauses a covered consumer's subscriptions. A paused listener
/// does not make an element active
/// (`element.dart`: `isActive => (listenerCount -
/// pausedActiveSubscriptionCount) > 0`), and the scheduler only flushes active
/// elements (`scheduler.dart::_performRefresh`) before clearing its queue
/// unconditionally — so the refresh this call queues is DROPPED rather than
/// run while the wizard is on top. That is not a leak: `invalidateSelf()` has
/// already severed the element's `KeepAliveLink`s and left
/// `_mustRecomputeState = true`, so the member is either disposed outright or
/// recomputed by the first READ after the wizard pops. Either way the day list
/// refetches on resume.
///
/// The consequence for callers: this helper guarantees the caches are DROPPED,
/// never that they have been REFILLED by the time it returns. Anything that
/// needs the new data in hand must read the provider itself. See
/// `bookings_day_notifier.dart`'s header ("What the queued refresh does and
/// does NOT guarantee") for the full mechanism.
///
/// Cycle-safe: neither target watches, even transitively,
/// `masterCreateBookingProvider`, so this closes no back-edge.
void invalidateBookingViewsAfterBookingCreated(Ref ref) {
  ref.invalidate(bookingsDayProvider);
  ref.invalidate(bookedDaysProvider);
}
