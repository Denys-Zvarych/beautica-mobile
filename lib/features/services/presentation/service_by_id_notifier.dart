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
@riverpod
Future<MasterService> serviceById(Ref ref, String id) async {
  // Cache-hit: check the in-memory list provider first.
  // `.value` returns the data when in AsyncData state, null otherwise.
  // ref.read is intentional here: we do not want to subscribe to list changes
  // while the edit screen is open, which would cause the provider to re-run
  // and flicker the edit form back to a loading state on any list refresh.
  final cached = ref.read(servicesListProvider).value;
  final hit = cached?.where((MasterService s) => s.id == id).firstOrNull;
  if (hit != null) return hit;

  // Cache-miss: network fetch via the repository.
  return ref.read(serviceRepositoryProvider).getMyService(id);
}
