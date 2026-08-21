// Phase 14.1 — navigation payload for the slot-picker route (`/booking/slots`
// and its nested `/booking/slots/time` step).
//
// Carries everything both the date and time screens need WITHOUT a second
// network round-trip: the target [master] (already loaded by
// [ServiceSelectorSheet] via `publicMasterProfileProvider`) and the client's
// [services] selection from Step 1. [masterId] is kept alongside [master] (not
// derived from it) so the slot picker never has to assume `master.id ==
// masterId` — it is always the exact id the flow was entered with.
//
// [services] is the client's FULL multi-selection from the Step 1 service
// picker (carried for DISPLAY — the "Послуги та ціни" summary shelf + the
// summed-duration chosen-window line, both per the approved
// `docs/signup-designs/BookingSlotPicker/` design). The underlying booking
// data layer (Phase 14.0 — `SlotRepository.getMasterSlots`,
// `CreateBookingRequest`) supports exactly ONE service per booking, so the
// slot picker and the `/booking/confirm` handoff operate on `services.first`
// as the PRIMARY (operative) service for slot-fetching and booking creation.
// This is a deliberate, documented scope boundary — see the file header of
// `slot_picker_screen.dart` for the full rationale — not an oversight.
//
// [rescheduleBookingId] is the reschedule extension point (Phase 14.8, wired):
// when non-null, `/booking/confirm`'s submit swaps the create POST for a
// `PATCH /bookings/{id}/reschedule` call.
//
// [rescheduleAppointmentId] is track 30.x's per-item VISIT counterpart
// (`PATCH /appointments/{id}/services/{bookingId}/reschedule`): non-null only
// when [rescheduleBookingId] identifies ONE service of a multi-service visit
// (`Booking.appointmentId != null`) — either footer of
// `booking_detail_screen.dart`'s `_onReschedule` may set it, the endpoint
// being dual-actor (the visit's own CLIENT or an assigned PROVIDER).
// [services] still carries exactly the ONE item being moved, mirroring the
// plain single-booking reschedule shape above — this per-item endpoint moves
// ONLY that service, never its siblings (no re-layout, no cascade, no
// gap-closing; the visit may legally become non-contiguous afterwards). This
// SUPERSEDES an earlier whole-VISIT reschedule flow that used to populate
// [services] with the visit's FULL ordered selection and call
// `PATCH /appointments/{id}/reschedule` — that mobile entry point was
// retired (the backend endpoint itself is untouched) once the backend grew
// the per-item route; see `BookingConfirmScreen._submit`, which checks
// [rescheduleAppointmentId] FIRST alongside [rescheduleBookingId].
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';
import 'create_master_booking_request.dart';

part 'booking_slot_picker_args.freezed.dart';

/// Navigation extra for `RouteNames.bookingSlots` / `RouteNames.bookingSlotsTime`.
@freezed
abstract class BookingSlotPickerArgs with _$BookingSlotPickerArgs {
  const factory BookingSlotPickerArgs({
    required String masterId,
    required Master master,

    /// The client's service selection from Step 1 (1..n). Never empty on a
    /// well-formed push — [ServiceSelectorSheet] only enables its "Далі" CTA
    /// once at least one service is selected.
    required List<MasterService> services,

    /// Non-null only when this flow was entered from the reschedule surface.
    /// See the file header. Set for BOTH a single-booking reschedule AND a
    /// whole-visit reschedule (in the latter case it identifies the ONE
    /// booking whose detail screen triggered the flow, not the routing
    /// target — see [rescheduleAppointmentId]).
    String? rescheduleBookingId,

    /// Non-null only for a track 27.x/MO-6 whole-VISIT reschedule. See the
    /// file header.
    String? rescheduleAppointmentId,

    /// Non-null only when this flow was entered from the master's own
    /// WALK-IN («Новий запис») entry point — the guest identity to submit
    /// with `CreateMasterBookingRequest`. See phase-258.
    WalkInGuest? guest,

    /// `true` when the viewer IS the master being booked (the walk-in path),
    /// so the slot/confirm screens must not render the master identity card
    /// back at them. Deliberately NOT derived from `guest != null` — see
    /// phase-258 D4. Defaults to `false` so every existing call site renders
    /// unchanged.
    @Default(false) bool hideMasterIdentity,
  }) = _BookingSlotPickerArgs;
}
