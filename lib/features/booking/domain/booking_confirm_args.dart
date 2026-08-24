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
// [rescheduleAppointmentId] is track 30.x's per-item VISIT counterpart: when
// non-null the submit instead swaps to
// `PATCH /appointments/{id}/services/{bookingId}/reschedule`
// (`AppointmentSubmit.rescheduleAppointmentItem`), moving ONLY the ONE
// service identified by [rescheduleBookingId] — siblings are untouched (no
// re-layout, no cascade, no gap-closing). [services] STILL holds exactly one
// element either way. Checked FIRST in `BookingConfirmScreen._submit`
// (alongside [rescheduleBookingId], which is always set too on this path —
// it identifies both the booking to move AND the one to
// invalidate/refetch on success). The endpoint itself is dual-actor (the
// visit's own CLIENT or an assigned PROVIDER); either footer of
// `booking_detail_screen.dart`'s `_onReschedule` may set it. This supersedes
// an earlier whole-VISIT reschedule flow (retired — the backend's own
// whole-visit endpoint is untouched, only this mobile entry point to it was
// removed) that used to populate [services] with the visit's FULL ordered
// selection.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';
import 'create_master_booking_request.dart';

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

    /// Non-null only when this flow was entered from the master's own
    /// WALK-IN («Новий запис») entry point — the guest identity to submit
    /// with `CreateMasterBookingRequest`. See phase-258.
    WalkInGuest? guest,

    /// `true` when the viewer IS the master being booked (the walk-in path),
    /// so this screen must not render the master identity card back at
    /// them. Deliberately NOT derived from `guest != null` — see phase-258
    /// D4. Defaults to `false` so every existing call site renders
    /// unchanged.
    @Default(false) bool hideMasterIdentity,

    /// Forwarded unchanged from [BookingSlotPickerArgs.rescheduleTargetIsWalkIn]
    /// by `SlotTimeScreen._confirm` — see that field's doc for the full
    /// rationale. `_submit` folds this into `BookingSuccessArgs.isWalkIn`
    /// alongside `guest != null`, so a walk-in RESCHEDULE hides the terminal
    /// screen's «Додати в календар» exactly like a walk-in CREATE, without
    /// disturbing the reschedule copy/CTA precedence (`isReschedule` is
    /// still checked FIRST wherever the two could otherwise conflict).
    /// Defaults to `false` so every existing call site is unaffected.
    @Default(false) bool rescheduleTargetIsWalkIn,

    /// RESCHEDULE-ONLY, client-identity parity fields (2026-08-22). Forwarded
    /// unchanged from [BookingSlotPickerArgs.rescheduleClientName] /
    /// [BookingSlotPickerArgs.rescheduleClientPhone] by `SlotTimeScreen
    /// ._confirm` — see that field's doc for the full rationale. `null` on
    /// every CREATE call site (client or walk-in) and on a CLIENT's own
    /// reschedule; non-null only when a PROVIDER rescheduled a booking with a
    /// registered client identity to show. Consumed by this screen to render
    /// [GuestIdentityCard.identity] in the same visual slot the walk-in
    /// [guest] card occupies, then forwarded onto [BookingSuccessArgs] for
    /// the terminal done screen.
    String? rescheduleClientName,
    String? rescheduleClientPhone,
  }) = _BookingConfirmArgs;
}
