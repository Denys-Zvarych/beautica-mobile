// Phase 7.7 — the master's own service catalogue, as a DATA-layer provider.
//
// ## Why this exists rather than `servicesListProvider`
//
// The same list is already fetched by `ServicesList`
// (`features/services/presentation/services_list_notifier.dart`). Booking's
// filter sheet cannot watch it: `presentation/` is the one layer a sibling
// feature may never import (see `ARCHITECTURE-mobile.md` § 3 — cross-feature
// imports go through `domain/` or `data/`, never `presentation/`). This
// provider is that reachable entry point, sitting next to the repository it
// calls.
//
// ## The duplicate fetch is deliberate, and it is one request
//
// Delegating either way round was considered and rejected. `ServicesList`
// cannot watch THIS provider, because six call sites across the services and
// master features invalidate the list after a create/edit/delete and expect a
// refetch — with a watch edge in between, invalidating the watcher re-reads the
// untouched cache and the services list silently stops refreshing after a save.
// That is a live-path regression traded for a startup request, which is a bad
// trade.
//
// So this is an independent `keepAlive` fetch: ONE extra
// `GET /independent-masters/me/services` per session, and every subsequent
// filter-sheet open is served from cache.
//
// ## Both halves of the cache are dropped together
//
// Being independent means this provider needs its OWN invalidation edge, and
// Phase 7.7 shipped without one: all six mutation sites invalidated
// `servicesListProvider` alone, so a service created mid-session never joined
// the «Послуга» filter universe until the app restarted. They now all call
// `invalidateMasterServiceCatalogues` (in `services_list_notifier.dart`), which
// drops both. Pinned — including a structural guard against a seventh call site
// reintroducing the direct invalidation — by
// `test/features/services/presentation/services_catalogue_invalidation_test.dart`.
//
// ## This provider must stay SUBSCRIBED while the filter is reachable
//
// An invalidated `keepAlive` provider with no listeners does not rebuild;
// Riverpod drops the state and defers the refetch to the next read. So a
// one-shot `ref.read` warm-up is not enough — after an invalidation the next
// reader gets `AsyncLoading` and, correctly refusing to render retained data
// (see below), shows NO services at all. `MasterBookingsScreen` therefore holds
// a dedicated zero-height `_ServiceCatalogueWarmer` that `ref.watch`es this
// provider, rather than reading it once in `initState`.
//
// ## Consumers must read `asData?.value`, never `.value`
//
// SEC: `AsyncValue.value` returns RETAINED previous data in `AsyncLoading` and
// `AsyncError`, not only in `AsyncData`. Because `logout()` deliberately does
// not invalidate feature providers, this provider is re-run by the repository
// swap and lands in `AsyncError` still holding the PREVIOUS master's catalogue
// — which on a shared device is one account's service names rendered into
// another's filter sheet.
//
// ## No facet endpoint (backend Phase 26.4)
//
// The option universe is the master's own catalogue, by design — the backend
// deliberately ships no "which services appear in my bookings" endpoint, and
// this must not be reconstructed client-side from a page of results (a page is
// not the result set). The accepted consequence: a DELETED service is absent
// from the catalogue, so its historical bookings cannot be filtered BY service.
// They remain fully visible unfiltered. This is expected behaviour, not a gap
// to work around.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'master_service_catalog_provider.g.dart';

/// The authenticated master's full service catalogue.
///
/// Resolves to an empty list (never throws) when no services are configured —
/// [ServiceRepository.listMyServices]'s contract. Consumers should treat an
/// empty catalogue as "no service filter is offerable", not as an error.
///
/// `keepAlive` so repeated filter-sheet opens cost zero requests; see the file
/// header for why this does not reuse `servicesListProvider`.
@Riverpod(keepAlive: true)
Future<List<MasterService>> masterServiceCatalog(Ref ref) {
  return ref.watch(serviceRepositoryProvider).listMyServices();
}
