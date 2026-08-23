// Phase 14.16 — SalonMasterSchedule: real per-master data for the salon
// booking flow's step-3 "Час" screen (one `PageView` slide per assigned
// master).
//
// Replaces the approved preview's mock `BookingMaster`/`BookingSelection`
// (`docs/signup-designs/SalonBookingTime/lib/widgets/booking_master.dart`)
// with real typed data: the master's identity (from [SalonMasterSummary],
// already loaded by `publicSalonProfileProvider`) plus the EXACT services
// resolved for them on `SalonMasterSelectionScreen` (carried forward via
// `SalonBookingTimeArgs.assignedServiceIdsByMaster`, looked up against
// `salonServiceCatalogProvider`'s typed [SalonCatalogService] entries — the
// same numeric priceMin/priceMax/priceType/durationMinutes fields
// `_AssignConfirmBar._totals` already sums on the previous screen, so this
// model never re-parses a display string, unlike the preview's
// `formatMinutes`/regex-based `_parsePrice`).
//
// ID-SPACE CORRECTION (post Phase 14.16/14.17 bugfix) — [services] carries
// [SalonCatalogService] entries keyed on the salon-wide CATALOG id
// (`ServiceDefinitionResponse.id`), which is fine for display (name/price/
// duration) but is NOT the id space the slot-availability endpoint needs. An
// earlier version of this file's header claimed [primaryService] (`services.
// first`, since removed) mirrored `booking_slot_picker_args.dart`'s
// `services.first` precedent for the independent-master flow — that was only
// true for the SELECTION (pick the first assigned service), not for the ID
// TYPE: the independent-master flow's `MasterService.id` is already the
// per-master assignment id, whereas `services.first.id` here was still the
// catalog id. [orderedMasterServiceIds] is the actual fix — see its own doc
// comment below for how each entry is resolved.
//
// Phase 270 — [orderedMasterServiceIds] is the ONLY id field this type
// carries. A prior revision also carried a scalar "primary assignment id"
// field (`services.first`'s own assignment id) alongside this list; that
// scalar sat next to a list of N services and both of its call sites
// silently dropped every service but the first when building a booking/slot
// request — the exact bug this list exists to prevent. It was deleted
// outright, not kept as a `=> orderedMasterServiceIds.first` getter, which
// would have preserved the
// same drop-defect under a new name. See Phase 270's doc for the full
// decision (D1).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../salon/domain/salon_service_catalog.dart';

part 'salon_master_schedule.freezed.dart';

/// One assigned master's slide worth of data: who they are, and the exact
/// services they will perform in this single appointment.
@freezed
abstract class SalonMasterSchedule with _$SalonMasterSchedule {
  const factory SalonMasterSchedule({
    required String masterId,
    required String firstName,
    required String lastName,
    required MasterType type,

    /// The master's own professional title, or `null` when unset — the
    /// identity card ([MasterStrip]) prefers it over the generic role label.
    /// Carried from the [SalonMasterSummary] the master-selection step already
    /// resolved, so the salon flow's card can render the SAME name/title/
    /// rating triple the independent flow's card does.
    String? professionalTitle,

    /// Average review rating, or `null` when the master has no reviews yet
    /// (mirrors [SalonMasterSummary.avgRating]'s own null-when-unrated
    /// contract — the card renders an em-dash for it).
    double? avgRating,

    /// Total number of reviews — the muted `(n)` suffix beside the rating.
    @Default(0) int reviewCount,

    /// This master's assigned services (1..n), in selection order — the SAME
    /// [SalonCatalogService] entries the catalogue screen carries, so
    /// pricing and duration are always the typed numeric fields, never
    /// re-derived from a display string. DISPLAY-ONLY (name/price/duration
    /// summation) — see [orderedMasterServiceIds] for the ids actually used
    /// to key the slot-availability query and the booking write.
    required List<SalonCatalogService> services,

    /// This master's OWN per-master-assignment ids
    /// (`MasterServiceResponse.id`), one per entry in [services], in the
    /// SAME back-to-back execution order — the chained-visit order
    /// `CreateAppointmentRequest{masterId, masterServiceIds[], startAt}`
    /// consumes on the walk-in and independent paths. Never sort this for
    /// display and never reorder it through `copyWith` — a reordered list
    /// silently reschedules the client's services.
    ///
    /// [SalonCatalogService.id] is the salon-wide CATALOG id
    /// (`ServiceDefinitionResponse.id`, from `GET /salons/{salonId}/services`)
    /// — a DIFFERENT id space from the per-master `MasterServiceAssignment`
    /// row the backend's `GET /masters/{masterId}/slots?...&serviceId=...`
    /// endpoint actually requires (confirmed via `backend-debugger`: passing
    /// the catalog id 404s with "masterService not found"). Each entry is
    /// resolved by matching the corresponding `services[i].id` against the
    /// master's own `GET /masters/{masterId}/services` list (via
    /// `salonMasterServiceCoverageProvider`, which already fetches that list
    /// for the master-assignment step and keeps the assignment id keyed by
    /// service-definition id instead of discarding it into a bare `Set`) —
    /// see `salon_time_screen.dart`'s `_resolveSchedule`. Mirrors what
    /// `MasterService.id` already represents for the independent-master flow
    /// (`slot_picker_screen.dart`), which has always been correct here.
    @Default(<String>[]) List<String> orderedMasterServiceIds,
  }) = _SalonMasterSchedule;

  const SalonMasterSchedule._();

  /// This master's summed appointment length — the window math uses this
  /// (chosen slot start → start + [summedDurationMinutes]), NOT the primary
  /// service's duration alone. See the architecture note in
  /// `salon_booking_schedule_notifier.dart` for why slot AVAILABILITY is
  /// still queried against the primary service only (an MVP approximation).
  int get summedDurationMinutes => services.fold<int>(
    0,
    (int sum, SalonCatalogService s) => sum + (s.durationMinutes ?? 0),
  );
}
