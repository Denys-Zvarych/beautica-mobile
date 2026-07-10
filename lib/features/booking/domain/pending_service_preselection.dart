// Cross-flow service pre-selection payload.
//
// Carries the service filter the CLIENT had active on the discovery search
// results screen INTO the booking flow they navigate into from a result card,
// so the matching service(s) arrive PRE-CHECKED on the booking Step 1 catalogue
// (independent-master `ServiceSelectorSheet` and `SalonServiceSelectionScreen`).
//
// [targetId] scopes the payload to exactly one provider (a master id OR a salon
// id): the booking screen only consumes a payload whose [targetId] matches the
// provider it is showing, so a stale payload can never pre-check the wrong
// provider's catalogue.
//
// [serviceTypeslugs] are the exact platform service-type slugs
// (`SearchFilters.serviceTypeSlugs` / `CategoryServiceOption.key`) the user
// filtered on — the SAME slug space the backend now surfaces on
// `MasterService.serviceTypeSlug` / `SalonCatalogService.serviceTypeSlug`.
// Matching is EXACT slug equality.
//
// [serviceTypeLabels] are the resolved Ukrainian display names for those slugs
// (from the loaded `CategoryServiceOption` list). They are a DEFENSIVE fallback
// only — used to match a catalogue tile whose own `serviceTypeSlug` is null;
// the slug is always preferred.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'pending_service_preselection.freezed.dart';

/// Immutable payload handed from discovery search results to the booking flow
/// so the matching service(s) start pre-checked on the booking catalogue.
@freezed
abstract class PendingServicePreselection with _$PendingServicePreselection {
  const factory PendingServicePreselection({
    /// The provider (master id OR salon id) this pre-selection applies to. A
    /// booking screen consumes the payload only when its own target id matches.
    required String targetId,

    /// Exact platform service-type slugs to pre-check. Empty is never stored
    /// (the setter is only called when a service filter is active).
    required Set<String> serviceTypeSlugs,

    /// Resolved Ukrainian display names for [serviceTypeSlugs]. Defensive
    /// fallback only — matched against a catalogue tile's service-type name
    /// when that tile has no slug of its own. Prefer the slug.
    required Set<String> serviceTypeLabels,
  }) = _PendingServicePreselection;
}
