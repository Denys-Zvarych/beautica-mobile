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
import 'booking_detail_notifier.dart';
import 'bookings_day_notifier.dart';
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
///     LIMITATION, accepted: this reaches only the PLAIN
///     `BookingsDayQuery.of(day: d)` member (no status/serviceId filters). A
///     FILTERED LRU entry for the same day — e.g. the rail narrowed to
///     CONFIRMED-only — is a different family key and is not caught here; it
///     goes stale until its own keepAlive window elapses or it is next
///     rebuilt naturally. That is a stale filtered view, never wrong data
///     rendered as fresh (the common, unfiltered view is always correct
///     immediately), so it is not worth widening this to every filter
///     combination that has ever touched [affectedDates].
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
///
/// Cost: one refetch per LIVE subscriber (Riverpod drops an invalidated
/// `autoDispose`/`keepAlive` provider with no listeners instead of refetching
/// eagerly), so calling this while none of these screens are on-screen costs
/// nothing.
void invalidateBookingViewsAfterExternalDecline(
  WidgetRef ref,
  Iterable<String> declinedBookingIds, {
  required Iterable<DateTime> affectedDates,
}) {
  for (final String id in declinedBookingIds) {
    ref.invalidate(bookingDetailProvider(id));
  }
  for (final DateTime day in affectedDates.toSet()) {
    ref.invalidate(bookingsDayProvider(BookingsDayQuery.of(day: day)));
  }
  ref.invalidate(myBookingsProvider(BookingTab.upcoming));
  ref.invalidate(myBookingsProvider(BookingTab.cancelled));
  ref.invalidate(nextAppointmentProvider);
}
