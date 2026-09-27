// Phase 7.7 — the master's own service catalogue, as a DATA-layer provider.
//
// ## This is THE fetch. Everything else wraps it. (N2, 2026-09-10)
//
// `GET /independent-masters/me/services` is issued in exactly one place in the
// app: here. Two surfaces consume it —
//
//   • «Мої послуги» (`presentation/services_list_notifier.dart`'s
//     `servicesListProvider`), which now `ref.watch`es this provider's
//     `.future` instead of calling the repository itself;
//   • the «Послуга» filter universe on the master's «Мої записи» (Phase 7.7),
//     which watches this provider directly.
//
// It lives in `data/`, next to the repository it calls, because `presentation/`
// is the one layer a sibling feature may never import (see
// `ARCHITECTURE-mobile.md` § 3 — cross-feature imports go through `domain/` or
// `data/`). That same rule FORCES the direction of the wrap: this provider
// cannot watch `servicesListProvider`, so `servicesListProvider` watches this.
//
// ### What changed, and why the old header said the opposite
//
// Until 2026-09-10 these were two INDEPENDENT `keepAlive` fetches, and the
// header here argued the duplication was a deliberate trade. The argument was:
// «six call sites invalidate the services list after a create/edit/delete and
// expect a refetch — with a watch edge in between, invalidating the WATCHER
// re-reads the untouched cache and the list silently stops refreshing after a
// save». That failure mode is real, and it is why the mutation edge now points
// UPSTREAM: every mutation, and every error-state retry, goes through
// `invalidateMasterServiceCatalogues(ref)`, which drops THIS provider — the
// shared fetch — so both surfaces refresh from one request. A call site that
// invalidates either provider directly is a structural test failure; see
// `test/features/services/presentation/services_catalogue_invalidation_test
// .dart`.
//
// Cost, measured by that test: ONE request when both surfaces are live, ONE
// when either is, ONE per mutation. It was two-and-two whenever both listeners
// coexisted.
//
// ## This provider must stay SUBSCRIBED while the filter is reachable
//
// An invalidated `keepAlive` provider with no listeners does not rebuild;
// Riverpod drops the state and defers the refetch to the next read. So a
// one-shot `ref.read` warm-up is not enough — after an invalidation the next
// reader gets `AsyncLoading` and, correctly refusing to render retained data
// (see below), shows NO services at all. `MasterBookingsScreen` therefore holds
// a dedicated zero-height `_ServiceCatalogueWarmer` that `ref.watch`es this
// provider, rather than reading it once in `initState`. (A live listener on
// `servicesListProvider` now also keeps this provider live transitively — but
// only while «Мої послуги» is mounted, which is exactly when «Мої записи» is
// not. The warmer is still load-bearing.)
//
// ## Consumers must read `asData?.value`, never `.value`
//
// SEC: `AsyncValue.value` returns RETAINED previous data in `AsyncLoading` and
// `AsyncError`, not only in `AsyncData`. Because `logout()` deliberately does
// not invalidate feature providers, this provider is re-run by the identity
// watch below and lands in `AsyncError` still holding the PREVIOUS master's
// catalogue — which on a shared device is one account's service names rendered
// into another's filter sheet.
//
// THE WRAP DOES NOT LAUNDER THIS (correction, 2026-09-10 — the previous
// wording of this paragraph claimed it did, and that claim is FALSE).
// `servicesListProvider` reads `.future`, and `.future` completing with the
// error buys exactly one thing: the wrapper can never land in **AsyncData**
// republishing stale data. It does NOT strip the retained value. Riverpod
// re-attaches it on every async transition — `element.dart:66` calls
// `copyWithPrevious`, and `AsyncError.copyWithPrevious` sets
// `value: previous._value` UNCONDITIONALLY, ignoring its own `isRefresh`
// parameter (riverpod-3.1.0 `async_value.dart:873-878`);
// `AsyncLoading.copyWithPrevious` retains it in BOTH branches (`:780-816`).
// So `servicesListProvider.value` inside `AsyncError` holds the previous
// account's catalogue byte-identically to this provider's.
//
// What actually protects the render path is two things, and BOTH must stay
// true:
//
//   • every consumer reads `asData?.value` or `.when` — `asData` is null
//     outside `AsyncData`, `.value` is not. This rule is MANDATORY downstream
//     of the wrapper exactly as much as it is here; the watch edge does not
//     excuse a single call site from it;
//   • an identity change is a DEPENDENCY change, so `isReload == true`
//     (`element.dart:563`) → `seamless: false` → the state reports
//     `isReloading`, and `.when`'s defaults (`skipLoadingOnReload: false`,
//     `skipError: false`) paint the spinner / the error body rather than the
//     retained list. Every consumer today uses `.when`.
//
// Direct `.value` readers were swept at the same time
// (`service_by_id_notifier.dart`, `service_setup_screen.dart`) and moved to
// `asData?.value`.
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
// [masterServiceCatalog] `ref.watch`es the authenticated user's id directly,
// mirroring `BookingsDayNotifier.build` / `bookedDays`'s identical fix —
// narrowed through the SHARED [authUserIdOrNull] selector, never the whole
// `AsyncValue<AuthSession>`, so a silent token refresh
// (`AuthNotifier.setAccessToken`, same id/new accessToken) stays a no-op for
// this cache instead of forcing a refetch on every silent refresh. (The
// selector was an inline hand-copied `switch` here until 2026-09-10; that is
// the eighth copy [authUserIdOrNull]'s own doc exists to prevent, so it now
// watches through the one definition. Behaviourally identical — `.select`
// compares the returned `String?`, not the closure.) Pinned by
// `test/features/services/data/master_service_catalog_provider_test.dart`.
//
// `servicesListProvider` carries its OWN copy of this watch and must keep it:
// the `.future` edge it reads is a coalescing channel that drops the auth
// boundary while a fetch is in flight. See that file's header.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/auth_notifier.dart';

part 'master_service_catalog_provider.g.dart';

/// The authenticated master's full service catalogue — the app's ONE
/// `GET /independent-masters/me/services`.
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
/// `keepAlive` so repeated filter-sheet opens cost zero requests. `ServicesList`
/// («Мої послуги») wraps this provider's `.future`; see the file header for the
/// forced import direction and for why mutations must invalidate THIS provider
/// rather than the wrapper.
/// Phase 317 — `dependencies: [serviceRepository]` is MANDATORY, not
/// decorative: without it this provider resolves against the ROOT container
/// even inside the salon-target `ProviderScope`, hands back the OPERATOR's own
/// catalogue, and the delete button on a service card would hit
/// `DELETE /services/{id}` (destroying a shared salon definition) instead of
/// the unassign endpoint. The guard assert is `kDebugMode`-only — see
/// [serviceRepositoryProvider]'s SCOPED-TARGET CONTRACT doc.
@Riverpod(keepAlive: true, dependencies: [serviceRepository])
Future<List<MasterService>> masterServiceCatalog(Ref ref) {
  // Security (mobile-security MEDIUM-2, 2026-07-20) — see the file header.
  // Explicit identity watch, independent of whatever `serviceRepositoryProvider`
  // happens to depend on today.
  ref.watch(authProvider.select(authUserIdOrNull));
  return ref.watch(serviceRepositoryProvider).listMyServices();
}
