// Phase 5.2 — Services list AsyncNotifier.
//
// Provides the full list of [MasterService] records owned by the authenticated
// master. Built on [riverpod_generator] — never hand-construct the provider.
//
// [build] delegates to [ServiceRepository.listMyServices], which returns an
// empty list (never throws) when the master has no services configured.
//
// [refresh] sets [AsyncLoading] immediately, re-fetches, and updates state.
// Callers (e.g. [RefreshIndicator]) should await this method; it never throws.
//
// keepAlive: true so that navigation away (e.g. push to create/edit screen)
// does not dispose the provider — enabling ref.invalidate(servicesListProvider)
// called after a save/delete to land on the active provider rather than a
// disposed one.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'services_list_notifier.g.dart';

/// Async notifier for the services list screen.
///
/// Kept alive (`keepAlive: true`) so that navigation away does not dispose
/// the provider; `ref.invalidate(servicesListProvider)` after create/edit/delete
/// always lands on the live provider and triggers a re-fetch.
@Riverpod(keepAlive: true)
class ServicesList extends _$ServicesList {
  bool _refreshing = false;

  @override
  Future<List<MasterService>> build() {
    return ref.watch(serviceRepositoryProvider).listMyServices();
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
