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

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'services_list_notifier.g.dart';

/// Async notifier for the services list screen.
///
/// Watches [serviceRepositoryProvider] so the list is automatically re-fetched
/// when the auth session changes (e.g. after login).
@riverpod
class ServicesList extends _$ServicesList {
  bool _refreshing = false;

  @override
  Future<List<MasterService>> build() =>
      ref.watch(serviceRepositoryProvider).listMyServices();

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
