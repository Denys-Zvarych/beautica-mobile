// MO-4 (single-master single-visit rework) — SalonMasterSchedule: the ONE
// chosen master's fully-resolved visit for the salon booking flow's time /
// confirm / success steps.
//
// The salon flow now mirrors the independent-master flow: the client
// multi-selects services (step 1), picks the ONE master who performs ALL of
// them (step 2 — the coverage INTERSECTION), then picks ONE date + ONE start
// time for the whole visit (step 3), submitted as a SINGLE `POST /appointments`
// (step 4). This type carries that chosen master's identity (from
// [SalonMasterSummary], already loaded by `publicSalonProfileProvider`) plus
// the EXACT services the client selected, in order — the same typed
// priceMin/priceMax/priceType/durationMinutes fields the summary shelf sums,
// so this model never re-parses a display string.
//
// ID-SPACE NOTE — [services] carries [SalonCatalogService] entries keyed on
// the salon-wide CATALOG id (`ServiceDefinitionResponse.id`), fine for display
// (name/price/duration) but NOT the id the slot-availability or
// `POST /appointments` endpoints need. [orderedMasterServiceIds] holds the
// chosen master's OWN per-master `MasterServiceAssignment` ids
// (`MasterServiceResponse.id`), aligned 1:1 with [services] order — resolved
// from `salonMasterServiceCoverageProvider` on the master-selection step. This
// mirrors what `MasterService.id` already represents for the independent flow.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../salon/domain/salon_service_catalog.dart';

part 'salon_master_schedule.freezed.dart';

/// The chosen master's visit: who they are, and the exact ordered services
/// they will perform back-to-back in this single appointment.
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

    /// The client's selected services (1..n), in selection order — the SAME
    /// [SalonCatalogService] entries the catalogue screen carries, so
    /// pricing and duration are always the typed numeric fields, never
    /// re-derived from a display string. DISPLAY-ONLY (name/price/duration
    /// summation) — see [orderedMasterServiceIds] for the ids used to key the
    /// slot-availability query and the `POST /appointments` submit.
    required List<SalonCatalogService> services,

    /// The chosen master's OWN per-master `MasterServiceAssignment` ids
    /// (`MasterServiceResponse.id`), aligned 1:1 with [services] order — the
    /// exact `masterServiceIds` sent to `POST /appointments` (back-to-back run
    /// order) and to the multi-service slot-availability query
    /// (`SlotRepository.getMasterSlots`).
    ///
    /// [SalonCatalogService.id] is the salon-wide CATALOG id
    /// (`ServiceDefinitionResponse.id`, from `GET /salons/{salonId}/services`)
    /// — a DIFFERENT id space from the per-master `MasterServiceAssignment`
    /// row the backend's `/slots` and `/appointments` endpoints require
    /// (passing the catalog id 404s "masterService not found"). These ids are
    /// resolved by matching each `services[i].id` against the chosen master's
    /// coverage map (via `salonMasterServiceCoverageProvider`) on the
    /// master-selection step — see `SalonMasterSelectionScreen._confirm`.
    required List<String> orderedMasterServiceIds,
  }) = _SalonMasterSchedule;

  const SalonMasterSchedule._();

  /// This visit's summed appointment length — the window math uses this
  /// (chosen slot start → start + [summedDurationMinutes]) for the confirm /
  /// success window labels. Slot AVAILABILITY (MO-2) is queried against ALL
  /// [orderedMasterServiceIds] as a summed block.
  int get summedDurationMinutes => services.fold<int>(
    0,
    (int sum, SalonCatalogService s) => sum + (s.durationMinutes ?? 0),
  );
}
