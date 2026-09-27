// Phase 328 — Bookings capability resolver (the «Записи» read-only gate).
//
// Resolves, from the auth/role state alone, what the current viewer may DO on
// the shared «Записи» surfaces — the `BookingsDiscoveryView` list and the
// `BookingDetailScreen` action footer. The track this belongs to gives an
// invited `SALON_MASTER` the SAME screens the `INDEPENDENT_MASTER` already
// uses, read-only: they may open a booking and read it, but never move it and
// never create one. Gating client-side (not relying on a backend 403 alone)
// is what keeps a read-only role from ever SEEING a write affordance.
//
// This is the booking-side sibling of
// `features/schedule/presentation/schedule_capability.dart` — same shape,
// same strict session read, same fail-closed default. Read that file's header
// first; the reasoning below does not repeat what it already explains.
//
// ## TWO booleans, not one
//
// The two surfaces are gated independently ON PURPOSE. They happen to share a
// role mapping today, but they answer different questions —
// "may this viewer MOVE an existing booking" versus "may this viewer CREATE
// one" — and the salon «Розклад» work that follows this track needs a
// DIFFERENT combination of the two (a salon-wide list where the viewer may
// create but the per-booking transitions stay on the assigned master). Fusing
// them into one `bookingsWritable` now would have to be split back apart
// then, with every call site re-audited. Two names, each with its own doc, is
// the cheaper shape.
//
// ## Role mapping (identical for both, today)
//
//   • INDEPENDENT_MASTER            → true  (their own bookings, their own
//                                            calendar — the MVP scope).
//   • SALON_OWNER / SALON_ADMIN     → true  (they run the salon's book).
//   • SALON_MASTER                  → false (invited, READ-ONLY — the role
//                                            this phase exists for).
//   • CLIENT                        → false (defensive; a client never
//                                            reaches a provider «Записи»
//                                            surface, but the arm is written
//                                            out rather than defaulted so
//                                            the `switch` stays exhaustive).
//   • null — loading / unauthenticated / unsettled session
//                                   → false (FAIL CLOSED; see below).
//
// ## There is deliberately NO third boolean for "may leave client feedback"
//
// The provider's «Залишити відгук про клієнта» CTA is driven by the SERVER's
// `Booking.providerCanReviewClient` flag, which already encodes every
// precondition (COMPLETED, owner, not already reviewed, not a walk-in). A
// client-side role map for the same question would be a SECOND source of
// truth that silently drifts the first time the backend's rule changes — the
// exact failure `booking_detail_screen.dart`'s `_actions` doc warns about for
// the client-side `canReview`. Do not add one.

// `flutter_riverpod` (alongside `riverpod_annotation`) is what brings
// `ProviderListenable.select` into scope — the same pair
// `schedule_capability.dart` imports for the same reason.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';

part 'bookings_capability.g.dart';

/// `true` when the current viewer may apply a STATUS TRANSITION to a booking
/// they are looking at — «Завершити» (complete), «Скасувати» (decline),
/// «Перенести» (reschedule) and not-complete.
///
/// Generated provider name: `bookingTransitionsEnabledProvider`.
///
/// `false` for `SALON_MASTER` — the invited, read-only role — and, fail-closed,
/// for `CLIENT` and for any session that is not a settled, authenticated
/// `AsyncData`. Gates `BookingDetailScreen`'s `_providerActions` footer
/// (phase 331); the review CTA in that same footer is NOT gated on this, see
/// the file header.
///
/// Watches through [authUserRoleSettledOrNull] — the STRICT selector, never
/// [authUserRoleOrNull] (mobile-security MEDIUM on the phase 309–311 track,
/// 2026-09-06, which is why `scheduleEditable` reads the strict one too). This
/// provider is a WRITE-GATE, so it must resolve read-only — not "whatever the
/// last known role was" — the instant the session is anything other than a
/// settled, authenticated `AsyncData`. The lenient `.value` unwrap
/// [authUserRoleOrNull] performs (correct for nav-target picks) would let a
/// STALE `Authenticated` ride a later `AsyncLoading`/`AsyncError` in via
/// Riverpod's automatic `copyWithPrevious` and keep granting transition
/// affordances after the session they were granted for stopped being
/// definitely valid. See [authUserRoleSettledOrNull]'s own doc for why the two
/// selectors must NOT be collapsed into one.
///
/// Selecting on the ROLE (rather than watching `authProvider` un-narrowed)
/// also keeps this provider silent across a silent token refresh:
/// `AuthNotifier.setAccessToken` emits a fresh `AsyncData(Authenticated(...))`
/// on every refresh (same user, new `accessToken`, which participates in
/// `Authenticated`'s `@freezed` equality), so an un-narrowed watch would
/// rebuild the whole booking-detail footer on each one (mobile-perf MEDIUM,
/// 2026-09-06).
@riverpod
bool bookingTransitionsEnabled(Ref ref) {
  final UserRole? role = ref.watch(
    authProvider.select(authUserRoleSettledOrNull),
  );
  return switch (role) {
    UserRole.independentMaster ||
    UserRole.salonOwner ||
    UserRole.salonAdmin => true,
    UserRole.salonMaster || UserRole.client || null => false,
  };
}

/// `true` when the current viewer may CREATE a booking by hand — the «Записи»
/// header's add (+) entry point.
///
/// Generated provider name: `bookingCreationEnabledProvider`.
///
/// Consumed by `MasterBookingsScreen`, which passes it into
/// `BookingsDiscoveryView.canCreateBooking` (phase 329). `false` makes the
/// button ABSENT, not disabled — a control that can never be tapped should
/// never be drawn (the same user-locked ruling that removed the disabled
/// «Перенести» caption in `booking_detail_screen.dart`'s `_providerActions`).
///
/// Same STRICT [authUserRoleSettledOrNull] read, for the same reason, as
/// [bookingTransitionsEnabled] — see that provider's doc. Kept SEPARATE from
/// it despite the identical role mapping today; the file header explains why
/// fusing the two would have to be undone by the salon «Розклад» work.
@riverpod
bool bookingCreationEnabled(Ref ref) {
  final UserRole? role = ref.watch(
    authProvider.select(authUserRoleSettledOrNull),
  );
  return switch (role) {
    UserRole.independentMaster ||
    UserRole.salonOwner ||
    UserRole.salonAdmin => true,
    UserRole.salonMaster || UserRole.client || null => false,
  };
}
