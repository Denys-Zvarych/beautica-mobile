// Phase 7.7 audit remediation (S2) — the ONE fan-out point for "the master's
// service catalogue changed".
//
// Deliberately its OWN file rather than a helper inside
// `services_list_notifier.dart`. Two reasons, one architectural and one
// mechanical:
//
//   • It is a different concern. The notifier owns one provider's lifecycle;
//     this owns the cross-provider consequence of a MUTATION.
//   • `scripts/forbid_provider_self_invalidation.sh` flags cross-provider
//     `ref.invalidate` inside a notifier file, and correctly so — that pattern
//     really can close a watch cycle, and since N2 `ServicesList` genuinely
//     WATCHES one of the providers invalidated below. This function is
//     top-level and takes a `WidgetRef`, so it structurally cannot run inside a
//     Notifier; hosting it here keeps that guard's signal honest instead of
//     spending a `// cycle-safe:` waiver on what would now be a real back-edge.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/presentation/service_catalogue_revision.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';

/// Invalidates EVERY cached view of the master's own service catalogue.
///
/// Since N2 (2026-09-10) there is exactly ONE cached FETCH —
/// [masterServiceCatalogProvider], the app's single
/// `GET /independent-masters/me/services` — and both surfaces read it:
///   • `servicesListProvider` (the «Мої послуги» screen) `ref.watch`es its
///     `.future`;
///   • the «Послуга» filter universe on «Мої записи» watches it directly.
///
/// BOTH lines below are load-bearing, for DIFFERENT reasons, and neither is
/// sufficient alone:
///
///   • [masterServiceCatalogProvider] is the line that actually RE-FETCHES.
///     Invalidating `servicesListProvider` alone rebuilds a wrapper that
///     re-reads an untouched upstream cache and refreshes nothing — the
///     silent-stale failure the pre-N2 header warned about, with the direction
///     reversed. Pinned by
///     `test/features/services/presentation/services_catalogue_invalidation_test.dart`
///     (all three behavioural cases go red without it).
///   • `servicesListProvider` is the line that makes an UNLISTENED reader see
///     the new data. Riverpod does not push an invalidation through to a
///     dependent with no live listener: the upstream drops its state and defers
///     the refetch, while the downstream keeps handing out its cached future
///     and never learns to rebuild. `ServiceSetupScreen._flagRowsNowOwned` is
///     exactly that shape — it invalidates and then
///     `await ref.read(servicesListProvider.future)` in the SAME turn, from a
///     screen that only ever `ref.read`s the list — and it silently answered
///     with the stale pre-save catalogue when this line was dropped. Pinned by
///     `test/features/services/presentation/service_setup_screen_test.dart`
///     ("_flagRowsNowOwned must re-read the catalogue after the invalidate"),
///     which goes red on exactly that mutation. It does NOT reproduce in a
///     harness that pumps a frame between the invalidate and the read — the
///     scheduler flush hides it — which is why the pin lives on the real
///     screen rather than in the invalidation unit test.
///
/// Because the wrapper only re-reads its upstream, the pair still costs ONE
/// request, not two. The structural half of the invalidation test also fails
/// the build on any direct invalidation of either provider outside this file.
///
/// Call this after any create / edit / delete — and from an error-state
/// «retry», which under one shared fetch is the same operation: drop the cache
/// and ask again.
///
/// Cost: ONE request per invalidation, however many surfaces are live. Before
/// N2 the two providers fetched independently, so a mutation made with both
/// listeners mounted cost two identical GETs.
///
/// A mutation made while BOTH surfaces are off-screen costs nothing — an
/// invalidated `keepAlive` provider with no listeners simply drops its state
/// and rebuilds on the next read.
///
/// That last property is also a trap, and it is why `MasterBookingsScreen`
/// holds a `_ServiceCatalogueWarmer` rather than warming the provider with a
/// one-shot `ref.read`: with NO listener the refetch is deferred to the next
/// read, so the sheet would open, trigger the fetch, and read `AsyncLoading` in
/// the same turn — rendering no «Послуга» section at all. Any future surface
/// that reads this catalogue needs a live subscription for the same reason.
void invalidateMasterServiceCatalogues(WidgetRef ref) {
  // The shared fetch — this is the line that re-requests.
  ref.invalidate(masterServiceCatalogProvider);
  // The wrapper — this is the line that makes an UNLISTENED reader see it.
  ref.invalidate(servicesListProvider);
  // 2026-09-13 audit (M7) — the "something happened to the catalogue" signal a
  // CALLER outside this subtree can observe across a push. See
  // `service_catalogue_revision.dart` for why a counter and not a pop result.
  // Bumped here, at the ONE fan-out point, rather than at the five mutation
  // sites, so it cannot drift away from the invalidation it describes.
  ref.read(serviceCatalogueRevisionProvider.notifier).bump();
}
