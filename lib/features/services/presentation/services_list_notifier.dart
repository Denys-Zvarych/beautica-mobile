// Phase 5.2 — Services list AsyncNotifier.
//
// Provides the full list of [MasterService] records owned by the authenticated
// master. Built on [riverpod_generator] — never hand-construct the provider.
//
// ## [build] no longer fetches — it WRAPS the one shared fetch (N2, 2026-09-10)
//
// This notifier used to call [ServiceRepository.listMyServices] itself, and so
// did [masterServiceCatalogProvider] (`data/master_service_catalog_provider
// .dart`). Two `keepAlive` providers, one identical
// `GET /independent-masters/me/services`, both invalidated together by
// `invalidateMasterServiceCatalogues` — so whenever both had a live listener,
// every catalogue mutation cost TWO identical requests. Today the master
// surface is four flat routes rather than a `StatefulShellRoute`, so the two
// listeners rarely coexist and the observed cost was one request; the structure
// permitted two and would have started charging them the day a shell route or a
// third surface appeared.
//
// [build] now `ref.watch`es [masterServiceCatalogProvider]`.future`. That
// provider is the single cached fetch: it lives in `data/` (so a sibling
// feature can reach it — `presentation/` is the one layer a sibling may never
// import), it is `keepAlive`, and it carries the explicit session-identity
// watch. This direction is forced: the catalogue provider CANNOT watch this one
// back, because `data/` may not import `presentation/`.
//
// Reading through `.future` (not `.value`) is deliberate, but it does NOT
// launder the retained-previous-account hazard documented on
// `master_service_catalog_provider.dart` — an earlier version of this comment
// said it did, and that was false. `.future` completes with the error, so this
// notifier can never land in [AsyncData] republishing a retained list. That is
// all it buys. The retained value is still THERE: riverpod re-attaches it on
// every async transition (`element.dart:66` → `copyWithPrevious`), and
// `AsyncError.copyWithPrevious` sets `value: previous._value` UNCONDITIONALLY,
// ignoring its `isRefresh` parameter (riverpod-3.1.0
// `async_value.dart:873-878`); `AsyncLoading.copyWithPrevious` retains it in
// both branches (`:780-816`). So `servicesListProvider.value` inside
// [AsyncError] holds the previous account's list byte-identically to the
// upstream's. `asData?.value` — or `.when`, which every consumer uses — is
// MANDATORY in this provider's consumers exactly as much as in the upstream's.
//
// ## Session identity is watched EXPLICITLY — the `.future` edge COALESCES
//
// [build] cannot take the auth boundary from the `.future` watch alone.
// `ElementWithFuture.onLoading` publishes a new future only
// `if (_futureCompleter == null)` (riverpod-3.1.0 `element.dart:81`). So while
// an upstream fetch is IN FLIGHT, an identity change rebuilds the upstream and
// publishes NO new future — [build] would not re-run, and a [refresh]-written
// `AsyncData` holding the PREVIOUS account's list would stay live and
// renderable into the new session until that in-flight future settled. Pre-N2
// this was unreachable: [build] watched `serviceRepositoryProvider` directly,
// which IS rebuilt on the auth boundary, so an identity change always
// discarded the hand-set state. The wrap removed that edge, so [build] keeps
// an explicit `ref.watch(authProvider.select(authUserIdOrNull))` — the same
// shared selector `masterServiceCatalogProvider` and `serviceRepositoryProvider`
// watch through, narrowed to the id so a silent token refresh stays a no-op.
// Pinned by `test/features/services/presentation/services_list_notifier_test
// .dart` ('an identity change during an IN-FLIGHT upstream fetch …').
//
// ## Why the mutation edge still goes UPSTREAM
//
// Invalidating THIS provider now re-reads the untouched upstream cache and
// changes nothing. Every mutation site — and every error-state retry — must go
// through `invalidateMasterServiceCatalogues(ref)`
// (`service_catalogue_invalidation.dart`), which drops the shared fetch and
// therefore refreshes both surfaces from ONE request. That is pinned, including
// a structural guard against a call site invalidating either provider directly,
// by `test/features/services/presentation/services_catalogue_invalidation_test
// .dart`.
//
// ## [refresh] deliberately still hits the repository directly
//
// [refresh] sets [AsyncLoading] SYNCHRONOUSLY, re-fetches, and updates state,
// guarded by `_refreshing`. Callers (e.g. [RefreshIndicator]) should await this
// method; it never throws. It does NOT invalidate the upstream, for two
// reasons:
//
//   • Correctness of the spinner. Derived state set by hand survives only until
//     the next upstream emission; an invalidate-and-await rewrite would hand
//     the loading/data sequence back to Riverpod and lose the synchronous
//     `AsyncLoading` that `RefreshIndicator` needs. A hand-set state here is
//     stable for as long as it should be: `build` re-runs only when the
//     upstream publishes a new future or — deliberately — when the SESSION
//     IDENTITY changes, and the latter discarding a hand-set list is the point
//     (see the identity section above), not collateral damage.
//   • `scripts/forbid_provider_self_invalidation.sh` correctly forbids a
//     cross-provider `ref.invalidate` inside a notifier file, and this notifier
//     now WATCHES the provider it would have to invalidate — precisely the
//     back-edge that gate exists to catch. Earning a `// cycle-safe:` waiver
//     here would spend the gate's signal on a real cycle.
//
// The accepted consequence is unchanged from before this refactor: a
// pull-to-refresh updates «Мої послуги» and leaves the «Послуга» filter
// universe on its previous cache until the next mutation or cold read. The two
// caches were fully independent before, so this is not a regression.
//
// keepAlive: true so that navigation away (e.g. push to create/edit screen)
// does not dispose the provider.

import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'services_list_notifier.g.dart';

/// Async notifier for the services list screen.
///
/// Kept alive (`keepAlive: true`) so that navigation away does not dispose the
/// provider. It is a thin view over [masterServiceCatalogProvider] — the single
/// cached `GET /independent-masters/me/services` — so a create/edit/delete must
/// invalidate THAT provider (via `invalidateMasterServiceCatalogues`) rather
/// than this one; see this file's header.
/// Phase 317 — BOTH direct edges are declared. `build` watches
/// [masterServiceCatalogProvider] (`:137`), but `refresh` additionally
/// `ref.read`s [serviceRepositoryProvider] (`:150`), and riverpod's transitive
/// closure does NOT cover a provider this one reads but does not go through —
/// measured: declaring only the catalogue throws
/// `Bad state: ServicesList depends on serviceRepositoryProvider, which may be
/// scoped` the first time `refresh()` runs (5 reds in
/// `services_list_notifier_test.dart`). Both are named for that reason; the
/// phase doc's one-entry table was wrong. See [serviceRepositoryProvider]'s
/// SCOPED-TARGET CONTRACT doc.
@Riverpod(
  keepAlive: true,
  dependencies: [masterServiceCatalog, serviceRepository],
)
class ServicesList extends _$ServicesList {
  bool _refreshing = false;

  @override
  Future<List<MasterService>> build() {
    // Session identity, watched EXPLICITLY and independently of the `.future`
    // edge below — that edge COALESCES (`element.dart:81`: a new future is
    // published only when no completer is outstanding), so an identity change
    // landing during an in-flight upstream fetch would not re-run this build
    // and a `refresh()`-written previous-account list would survive into the
    // new session. See the header.
    ref.watch(authProvider.select(authUserIdOrNull));
    // `.future`, never `.value`: an errored upstream must surface HERE as
    // AsyncError rather than as AsyncData republishing a retained
    // previous-account list. `.value` inside AsyncError/AsyncLoading still
    // CARRIES that list — consumers read `asData?.value`. See the header.
    return ref.watch(masterServiceCatalogProvider.future);
  }

  /// Pull-to-refresh: shows loading spinner immediately, re-fetches, updates.
  ///
  /// Guard prevents a refresh storm: if a refresh is already in-flight,
  /// subsequent calls are silently dropped instead of stacking.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      state = const AsyncLoading();
      state = await AsyncValue.guard(
        () => ref.read(serviceRepositoryProvider).listMyServices(),
      );
    } finally {
      _refreshing = false;
    }
  }
}
