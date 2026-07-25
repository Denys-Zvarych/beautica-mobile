// Navigation payload for the `/booking/confirm` route (independent-master
// booking flow's final review-and-submit step).
//
// MO-3 (single-visit rework): the client multi-selects several services in
// Step 1 and picks ONE date + ONE start time for the WHOLE visit on the time
// step (`SlotTimeScreen`). The services run back-to-back from [startAt]; the
// whole visit is submitted as ONE `POST /appointments`
// (`CreateAppointmentRequest`) — replacing the pre-MO-3 "N `POST /bookings`,
// one per service" fan-out. So this payload carries the ordered [services]
// selection, the single [startAt], and ONE stable [idempotencyKey] for the
// visit (never one-per-service).
//
// ORDER IS LOAD-BEARING: [services] is the exact order the services will run
// in — the same order flows to the availability request (`getMasterSlots`) and
// to `CreateAppointmentRequest.masterServiceIds`, where the backend chains the
// items back-to-back in that sequence.
//
// [master] is carried forward from `BookingSlotPickerArgs` so the confirm/
// success screens can render the master-identity card without a fresh network
// read (they still re-watch `publicMasterProfileProvider` to resolve the
// master + validate the services against the warmed cache).
//
// [rescheduleBookingId] is the reschedule extension point (track 14.8): when
// non-null the flow is a RESCHEDULE of a single EXISTING booking — [services]
// then holds exactly one element and the submit swaps `POST /appointments` for
// `PATCH /bookings/{id}/reschedule` (see `booking_notifier.dart`'s
// `AppointmentSubmit`). [idempotencyKey] / [clientComment] are create-only and
// unused on that path.
//
// [rescheduleAppointmentId] is track 27.x/MO-6's whole-VISIT counterpart: when
// non-null the submit instead swaps to `PATCH /appointments/{id}/reschedule`
// (`AppointmentSubmit.rescheduleAppointment`), moving EVERY service in the
// visit in lockstep — [services] then holds the visit's FULL ordered
// selection, not one element. Checked FIRST in `BookingConfirmScreen._submit`
// (before [rescheduleBookingId]) since both may be set together —
// [rescheduleBookingId] still carries the ONE booking id to invalidate/refetch
// on success, it just no longer decides which endpoint is called once this
// field is set. The endpoint itself is dual-actor (the visit's own CLIENT or
// an assigned PROVIDER); only the PROVIDER/master footer invokes it in-app
// today (see `booking_detail_screen.dart`'s `_onReschedule`).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';

part 'booking_confirm_args.freezed.dart';

/// Navigation extra for `RouteNames.bookingConfirm`.
@freezed
abstract class BookingConfirmArgs with _$BookingConfirmArgs {
  const factory BookingConfirmArgs({
    required String masterId,

    /// The visit's ordered service selection (1..10). Never empty on a
    /// well-formed push — the time step's «Підтвердити» CTA only enables once a
    /// start time is chosen for a non-empty selection. Order is the back-to-back
    /// running order (see the file header).
    required List<MasterService> services,

    /// The client's chosen start for the WHOLE visit (its first service).
    required DateTime startAt,

    /// A single UUID v4 for the whole visit, generated ONCE when these args were
    /// built (in `SlotTimeScreen._confirm`) and reused on every retry of the
    /// SAME submit so an ambiguously-failed `POST /appointments` de-duplicates
    /// server-side rather than double-booking. Unused on the reschedule path.
    required String idempotencyKey,

    /// The target master, carried forward for the confirm/success recap.
    /// Optional so a caller without it can still push (the provider fallback
    /// re-resolves the master).
    Master? master,

    /// Non-null only when this flow was entered from the reschedule surface —
    /// see the file header.
    String? rescheduleBookingId,

    /// Non-null only for a track 27.x/MO-6 whole-VISIT reschedule — see the
    /// file header.
    String? rescheduleAppointmentId,
  }) = _BookingConfirmArgs;
}
