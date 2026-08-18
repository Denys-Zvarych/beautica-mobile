// Phase 14.12/14.13 — navigation payload shared by the salon booking flow's
// service-selection step (`/booking/salon/services`) and master-assignment
// step (`/booking/salon/masters`).
//
// The salon booking model is fundamentally different from the
// independent-master flow (`BookingSlotPickerArgs`): a salon booking spans the
// salon's FULL catalogue, multi-selects several services possibly across
// categories, then assigns each selected service to one of potentially
// several masters — never a single `masterId`. [SalonBookingMasterSelectionArgs]
// carries exactly the two pieces of state the master-selection screen needs to
// resume that flow: which salon, and which service ids the client picked in
// step 1. The master-selection screen re-derives eligible masters + their
// service coverage from already-loaded data (see
// `salon_master_coverage_notifier.dart`) rather than the caller pre-computing
// it, so this payload stays deliberately minimal.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'salon_master_schedule.dart';

part 'salon_booking_args.freezed.dart';

/// Navigation extra for `RouteNames.salonBookingMasters`.
@freezed
abstract class SalonBookingMasterSelectionArgs
    with _$SalonBookingMasterSelectionArgs {
  const factory SalonBookingMasterSelectionArgs({
    required String salonId,

    /// The client's service selection from `SalonServiceSelectionScreen`
    /// (step 1). Never empty on a well-formed push — that screen's "Далі" CTA
    /// only enables once at least one service is selected.
    required List<String> selectedServiceIds,
  }) = _SalonBookingMasterSelectionArgs;
}

// MO-4 (single-master single-visit rework) — navigation payload for the salon
// booking flow's step-3 "Час" screen (`RouteNames.salonBookingTime`), pushed
// by `SalonMasterSelectionScreen`'s «Далі» CTA.
//
// The salon flow now books ONE visit against ONE chosen master who performs
// ALL selected services. This carries the fully-resolved [visit] (the chosen
// master + ordered services + per-master assignment ids), so the time / confirm
// screens need no re-fetch of the coverage map or catalogue to resolve it —
// only the salon address (a secondary read on the confirm/success screens).
// REPLACES the pre-MO-4 `{selectedServiceIds, assignedServiceIdsByMaster}`
// per-master assignment map.

/// Navigation extra for `RouteNames.salonBookingTime`.
@freezed
abstract class SalonBookingTimeArgs with _$SalonBookingTimeArgs {
  const factory SalonBookingTimeArgs({
    required String salonId,

    /// The chosen master + ordered selected services + per-master assignment
    /// ids, resolved on `SalonMasterSelectionScreen`.
    required SalonMasterSchedule visit,
  }) = _SalonBookingTimeArgs;
}
