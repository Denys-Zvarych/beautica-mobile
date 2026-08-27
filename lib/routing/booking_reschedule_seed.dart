// Phase 27.2 follow-up — the "is this booking-flow navigation a RESCHEDULE?"
// predicate.
//
// Track 27.2 widened `PATCH /bookings/{id}/reschedule` to providers, and
// `booking_detail_screen.dart` renders the «Перенести» CTA for an
// INDEPENDENT_MASTER on its own booking. The reschedule flow re-enters the
// CLIENT booking surfaces (`/booking/slots`, `/booking/slots/time`,
// `/booking/confirm`, `/booking/success`) to reuse the one slot picker rather
// than forking a provider-only copy of it — but those four routes carry
// `clientOnlyGuard`, which bounced the master straight back to
// `/master/profile` before the picker could mount.
//
// The rule "providers stay out of the CLIENT booking flow" is NARROWED, not
// deleted: only a navigation whose `extra` is a reschedule-shaped seed is
// admitted. A CREATE-shaped seed (no `rescheduleBookingId` /
// `isReschedule == false`) still bounces, and `/booking/new` — step 1 of the
// CREATE flow, which reschedule never enters — stays fully CLIENT-only.
//
// SEC: `extra` is in-app-only state handed to `GoRouter` by a call site inside
// this app. It cannot be forged from a deep link — an external link carries
// `extra == null`, which is `false` here and falls through to the unchanged
// `clientOnlyGuard` → `roleHomePath` bounce. Server authorization on
// `PATCH …/reschedule` is unchanged and remains the authoritative check; this
// predicate only decides which SCREEN mounts.
//
// Pure function: no Flutter, no Riverpod, no side effects — trivially testable,
// mirroring `role_home.dart`.
//
// Phase 259 — a SECOND provider-minted seed, the master's own WALK-IN
// («Новий запис») entry point, needs the exact same admission onto the four
// CLIENT booking routes, for the exact same reason: reuse the one slot
// picker rather than forking a provider-only copy of it. [isBookingWalkInSeed]
// is added as a SIBLING predicate — [isBookingRescheduleSeed] above keeps its
// exact name, signature and behaviour unchanged — and [isBookingProviderSeed]
// is the single OR of the two that the four route guards now consult.
//
// SEC (restated, not superseded): `state.extra` remains in-app-only and
// unreachable from a deep link — `extra == null` is `false` in both new
// predicates and falls straight through to the unchanged `clientOnlyGuard`
// bounce. Audit-fix cycle 2 (FIX 3, 2026-08-21) — CORRECTED CITATION:
// `unauthenticated_deeplink_redirect_test.dart` contains no reference to any
// `/booking/*` route and does not pin this. The actual coverage is
// `test/routing/booking_walkin_seed_test.dart`'s null-/wrong-typed-`extra`
// unit tests on `isBookingWalkInSeed` / `isBookingProviderSeed` (the "is
// false for a null extra (the deep-link case)" cases) plus
// `test/routing/booking_route_guard_test.dart`'s "malformed extra guard"
// group. Server authorization is unchanged and authoritative: `POST
// /bookings/staff` is
// role-gated on the backend (track 22.4,
// `phase-171-22.4-staff-booking-endpoint-and-authz`). The only new exposure
// is that a CLIENT-role session carrying a (never constructible in practice)
// guest-seeded `BookingSlotPickerArgs` would also skip the bounce — but
// `clientOnlyGuard` only ever bounced NON-clients, so this changes nothing
// for a client. Net role surface added: provider roles only. Flagged for
// `mobile-security` review — see phase-259.

import '../features/booking/domain/booking_confirm_args.dart';
import '../features/booking/domain/booking_slot_picker_args.dart';
import '../features/booking/domain/booking_success_args.dart';

/// Whether [extra] is a booking-flow argument object seeded by the RESCHEDULE
/// entry point rather than the CREATE entry point.
///
///   * [BookingSlotPickerArgs] / [BookingConfirmArgs] — reschedule iff
///     `rescheduleBookingId` is non-null (the booking being moved).
///   * [BookingSuccessArgs] — reschedule iff `isReschedule` (that class carries
///     the flag rather than the id, since the recap only needs the copy switch).
///   * anything else, including `null` (an external deep link) — `false`.
bool isBookingRescheduleSeed(Object? extra) => switch (extra) {
  BookingSlotPickerArgs(:final rescheduleBookingId) =>
    rescheduleBookingId != null,
  BookingConfirmArgs(:final rescheduleBookingId) => rescheduleBookingId != null,
  BookingSuccessArgs(:final isReschedule) => isReschedule,
  _ => false,
};

/// Whether [extra] is a booking-flow seed minted by the master's own WALK-IN
/// («Новий запис») entry point.
bool isBookingWalkInSeed(Object? extra) => switch (extra) {
  BookingSlotPickerArgs(:final guest) => guest != null,
  BookingConfirmArgs(:final guest) => guest != null,
  BookingSuccessArgs(:final isWalkIn) => isWalkIn,
  _ => false,
};

/// Whether [extra] is any PROVIDER-minted booking-flow seed — reschedule or
/// walk-in. The single predicate the four CLIENT booking routes consult.
bool isBookingProviderSeed(Object? extra) =>
    isBookingRescheduleSeed(extra) || isBookingWalkInSeed(extra);
