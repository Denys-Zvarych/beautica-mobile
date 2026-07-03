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
