// Public salon profile — "filter masters by selected service" state.
//
// Holds the ONE service the client has tapped in the "Послуги" tab to narrow
// the "Майстри" grid down to only the masters who perform it. Null = no filter
// (the default — every master shows).
//
// Kept as its own tiny `@riverpod` family (keyed on [salonId]) rather than
// screen-local `setState` because the SELECTING widget (the services-tab
// accordion) and the CONSUMING widgets (the masters grid + its active-filter
// chip) live in sibling subtrees under `PublicSalonProfileScreen` — a shared
// provider is the clean cross-subtree channel, and keying on [salonId] keeps
// two different salon profiles' selections independent.
//
// autoDispose (the codegen default): once the profile screen is popped nothing
// watches this family, so the selection resets on the next visit — a filter is
// a per-visit affordance, never persisted. The screen's top-level build watches
// it, so it stays alive across in-screen tab switches while the profile is open.
//
// Membership itself (does master X perform service Y) is NOT stored here — that
// comes from the existing `salonMasterServiceCoverageProvider` (bookable-masters
// read), which the masters grid cross-references against this selection's
// [SalonServiceSelection.id].

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'salon_service_filter_notifier.g.dart';

/// The service the client picked to filter the salon's masters by: the catalog
/// service id (comparable against `SalonCatalogService.id` and the keys of
/// `salonMasterServiceCoverageProvider`) plus its display name for the chip.
typedef SalonServiceSelection = ({String id, String name});

/// Which service (if any) the masters grid is currently filtered by, for the
/// salon identified by [salonId].
///
/// Generated provider name: `salonServiceFilterProvider` (a family — call it
/// with the target salon id).
@riverpod
class SalonServiceFilter extends _$SalonServiceFilter {
  @override
  SalonServiceSelection? build(String salonId) => null;

  /// Sets [service] as the active filter (replacing any previous one).
  void select(SalonServiceSelection service) => state = service;

  /// Toggles [service]: selects it, or clears the filter if it was already the
  /// active one.
  void toggle(SalonServiceSelection service) =>
      state = state?.id == service.id ? null : service;

  /// Clears the filter — every master shows again.
  void clear() => state = null;
}
