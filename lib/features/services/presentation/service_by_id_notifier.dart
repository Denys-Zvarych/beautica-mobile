// Phase 5.4 — Service-by-id provider.
//
// Cache-first: checks the in-memory list from [servicesListProvider] before
// going to the network. A cache miss falls back to [ServiceRepository.getMyService],
// which itself fetches the full list and filters by id (the backend has no
// single-resource GET endpoint in the current API version).
//
// Using `@riverpod` (autoDispose family): the provider is disposed when the
// edit screen leaves the widget tree, preventing stale service data from
// lingering after the screen is popped.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'service_by_id_notifier.g.dart';

/// Resolves a [MasterService] by its assignment [id].
///
/// Cache path (cheap): if [servicesListProvider] already holds a fully-resolved
/// list, we return the matching entry immediately — no network round-trip.
///
/// Fallback path (network): on a cache miss (or if the list is still loading
/// or errored), delegates to [ServiceRepository.getMyService] which fetches
/// the full list and filters client-side.
///
/// READINESS SELF-HEAL (the reason the two dependencies are read differently)
/// -------------------------------------------------------------------------
/// [serviceRepositoryProvider] itself does
/// `ref.watch(masterProfileProvider).value?.id ?? ''` and
/// [ServiceRepository.getMyService] opens with a readiness guard that throws
/// [UnauthorizedFailure] on an empty master id. On a COLD deep-link straight
/// to `/services/:id/edit` the master profile has not resolved yet, so the
/// first build of this provider fails that guard.
///
/// `UnauthorizedFailure` is deterministic, so `beauticaProviderRetry` (the
/// app-wide predicate installed in `main.dart`) correctly refuses to retry it.
/// That removed the accidental crutch this provider used to lean on: Riverpod's
/// blanket backoff re-ran the build at +200 ms, by which point the profile had
/// resolved, and the failure vanished. With the crutch gone the only way back
/// to a good state is a real subscription — hence `ref.watch` below, mirroring
/// what [servicesList] already does. Do NOT try to detect readiness by
/// inspecting `masterProfileProvider.value == null`: Riverpod 3's
/// `ref.invalidate` retains the previous `.value` (seamless reload), so that
/// check reads stale-true. Watching the source is the correct shape.
@riverpod
Future<MasterService> serviceById(Ref ref, String id) async {
  // Cache-hit: check the in-memory list provider first.
  // `.value` returns the data when in AsyncData state, null otherwise.
  // ref.read is intentional AND STAYS read: subscribing to list changes while
  // the edit screen is open would re-run this provider — flickering the edit
  // form back to a loading state (and discarding in-progress edits) on any
  // list refresh, including the `ref.invalidate(servicesListProvider)` the
  // save path fires. The list is a pure optimisation here; it is never what
  // unblocks a failed build.
  final cached = ref.read(servicesListProvider).value;
  final hit = cached?.where((MasterService s) => s.id == id).firstOrNull;
  if (hit != null) return hit;

  // Cache-miss: network fetch via the repository.
  //
  // ref.watch (NOT read): the repository handle is re-created when the master
  // profile resolves, and that new handle is precisely what turns the
  // readiness `UnauthorizedFailure` above into a successful fetch. A `read`
  // takes a snapshot of the not-yet-ready repository and registers no
  // dependency, so the error state would be terminal until the user tapped
  // «retry» by hand. The re-run cost is bounded: the repository is a keepAlive
  // singleton rebuilt only when the profile itself changes, which cannot
  // happen from the edit screen (this provider is autoDispose and is gone by
  // the time the profile screen can be reached).
  return ref.watch(serviceRepositoryProvider).getMyService(id);
}
