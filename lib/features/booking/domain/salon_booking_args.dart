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

// Phase 14.16 — navigation payload for the salon booking flow's step-3
// "Час" screen (`RouteNames.salonBookingTime`), pushed by
// `SalonMasterSelectionScreen`'s «Підтвердити» CTA.
//
// DEVIATION from the Phase 14.16 phase doc's one-line sketch
// (`SalonBookingTimeArgs { salonId, selectedServiceIds }`): this also carries
// [assignedServiceIdsByMaster] — the EXACT per-master assignment the client
// resolved on `SalonMasterSelectionScreen`, INCLUDING any contested-service
// choice made via that screen's resolver chips (a selected service performed
// by 2+ picked masters, where the client explicitly tapped which one gets
// it). Without this, `SalonTimeScreen` would have no way to reconstruct that
// choice — recomputing eligibility fresh from
// `salonMasterServiceCoverageProvider` + [selectedServiceIds] alone can only
// ever re-derive the masters/services, never WHICH candidate the client
// picked for a contested service, so that choice would be silently
// discarded. This is necessary to satisfy the phase doc's own acceptance
// criterion ("Slider shows exactly the masters assigned in step 2, with
// correct per-master service/duration summary") — not an embellishment.

/// Navigation extra for `RouteNames.salonBookingTime`.
@freezed
abstract class SalonBookingTimeArgs with _$SalonBookingTimeArgs {
  const factory SalonBookingTimeArgs({
    required String salonId,

    /// The client's full service selection from step 1 — carried alongside
    /// [assignedServiceIdsByMaster] (rather than re-derived from it) so a
    /// service that somehow resolved to no master (should never happen once
    /// `SalonMasterSelectionScreen`'s "Далі" CTA is enabled) is still
    /// traceable for debugging.
    required List<String> selectedServiceIds,

    /// masterId → the services (by [SalonCatalogService.id]) assigned to
    /// them, in roster order. Every value list is non-empty — a master only
    /// appears here once ≥1 service resolved to them.
    required Map<String, List<String>> assignedServiceIdsByMaster,
  }) = _SalonBookingTimeArgs;
}
