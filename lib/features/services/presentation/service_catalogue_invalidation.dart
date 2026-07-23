// Phase 7.7 audit remediation (S2) — the ONE fan-out point for "the master's
// service catalogue changed".
//
// Deliberately its OWN file rather than a helper inside
// `services_list_notifier.dart`. Two reasons, one architectural and one
// mechanical:
//
//   • It is a different concern. The notifier owns one provider's lifecycle;
//     this owns the cross-provider consequence of a MUTATION, and it will grow
//     a third entry the day a third surface caches the catalogue.
//   • `scripts/forbid_provider_self_invalidation.sh` flags cross-provider
//     `ref.invalidate` inside a notifier file, and correctly so — that pattern
//     really can close a watch cycle. This function is top-level and takes a
//     `WidgetRef`, so it structurally cannot run inside a Notifier; hosting it
//     here keeps that guard's signal honest instead of spending a
//     `// cycle-safe:` waiver on a false positive.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';

/// Invalidates EVERY cached view of the master's own service catalogue.
///
/// There are two, and they are independent fetches by design (see
/// `master_service_catalog_provider.dart`'s header for why neither can watch
/// the other):
///   • [servicesListProvider] — the «Мої послуги» screen.
///   • [masterServiceCatalogProvider] — the «Послуга» filter universe on the
///     master's «Мої записи» (Phase 7.7).
///
/// Call this after any create / edit / delete instead of invalidating either
/// one directly. Phase 7.7 shipped the catalogue provider `keepAlive` with NO
/// invalidation edge at all, so a service added mid-session never appeared in
/// the filter until the app was restarted — six call sites invalidated the list
/// and left the catalogue stale. One function is what stops the seventh call
/// site from reintroducing that.
///
/// Cost: one refetch per LIVE subscriber, not one per call. Neither provider is
/// watched from anywhere but the screen that needs it, so a mutation made while
/// «Мої записи» is off-screen costs nothing — an invalidated `keepAlive`
/// provider with no listeners simply drops its state and rebuilds on the next
/// read.
///
/// That last property is also a trap, and it is why
/// `MasterBookingsScreen` holds a `_ServiceCatalogueWarmer` rather than warming
/// the provider with a one-shot `ref.read`: with NO listener the refetch is
/// deferred to the next read, so the sheet would open, trigger the fetch, and
/// read `AsyncLoading` in the same turn — rendering no «Послуга» section at
/// all. Any future surface that reads this catalogue needs a live subscription
/// for the same reason.
void invalidateMasterServiceCatalogues(WidgetRef ref) {
  ref.invalidate(servicesListProvider);
  ref.invalidate(masterServiceCatalogProvider);
}
