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
