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
//
// ## Session identity is watched EXPLICITLY (mobile-security MEDIUM-2,
// 2026-07-20) — do not rely on the `serviceRepositoryProvider` cascade alone
//
// This `keepAlive` provider's only protection against serving a previous
// account's service names across a logout was, until this fix, INCIDENTAL:
// `ref.watch(serviceRepositoryProvider)` transitively watches
// `masterProfileProvider`, which itself watches `authProvider` — so an
// identity change happened to cascade through two hops. That chain is
// convention, not a guarantee: it silently stops protecting this provider the
// moment `serviceRepositoryProvider` is ever refactored to source its
// `masterId` some other way, and it was already only half the story — the
// "Consumers must read `asData?.value`, never `.value`" rule above is the
// OTHER half, and depends on every future call site remembering it.
//
// [masterServiceCatalog] now `ref.watch`es the authenticated user's id
// directly, mirroring `BookingsDayNotifier.build` /
// `bookedDays`'s identical fix — narrowed to `.select((s) => ...id)`, never
// the whole `AsyncValue<AuthSession>`, so a silent token refresh
// (`AuthNotifier.setAccessToken`, same id/new accessToken) stays a no-op for
// this cache instead of forcing a refetch on every silent refresh.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';

part 'master_service_catalog_provider.g.dart';

/// The authenticated master's full service catalogue.
///
/// Resolves to an empty list when the master has no services configured — but
/// ONLY for a well-formed empty response. This provider is NOT error-free:
/// [ServiceRepository.listMyServices] throws a `Failure` on any transport or
/// HTTP error, and (since the null-envelope fix) also on a 200 whose envelope
/// carries a null `data`, because a malformed success must never be
/// presentable as an empty catalogue. Consumers must therefore handle the
/// [AsyncError] state, and treat an EMPTY catalogue — not a failed one — as
/// "no service filter is offerable".
///
/// `keepAlive` so repeated filter-sheet opens cost zero requests; see the file
/// header for why this does not reuse `servicesListProvider`.
@Riverpod(keepAlive: true)
Future<List<MasterService>> masterServiceCatalog(Ref ref) {
  // Security (mobile-security MEDIUM-2, 2026-07-20) — see the file header.
  // Explicit identity watch, independent of whatever `serviceRepositoryProvider`
  // happens to depend on today.
  ref.watch(
    authProvider.select(
      (AsyncValue<AuthSession> session) => switch (session.value) {
        Authenticated(:final User user) => user.id,
        Unauthenticated() || null => null,
      },
    ),
  );
  return ref.watch(serviceRepositoryProvider).listMyServices();
}
