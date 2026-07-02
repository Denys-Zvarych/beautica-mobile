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
// [rescheduleBookingId] is an unused extension point for Phase 14.8
// (change/reschedule booking): when non-null, a future phase will swap the
// `/booking/confirm` POST for a `PATCH .../reschedule` call. Accepted now so
// the reschedule flow can reuse this exact screen pair without a route-shape
// change; no behavior is wired to it yet.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';

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

    /// Non-null only when this flow was entered from the Phase 14.8
    /// reschedule surface. See the file header — not wired to any behavior
    /// yet in this phase.
    String? rescheduleBookingId,
  }) = _BookingSlotPickerArgs;
}
