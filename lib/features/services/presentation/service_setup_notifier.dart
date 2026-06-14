// First-time service setup — bulk-save AsyncNotifier.
//
// Drives the one-pass empty-state setup screen. The screen owns all per-row UI
// state (selected categories, include toggles, duration/price controllers); this
// notifier owns only the SAVE side effect: it collects the assembled
// [MasterServiceBulkItem]s, POSTs them via [ServiceRepository.bulkCreate], and
// exposes a void [AsyncValue] the screen watches to gate its CTA + surface
// errors.
//
// On success the screen invalidates [servicesListProvider] and navigates to the
// (now-populated) services list. A 409 (the master already has services) surfaces
// as [MasterAlreadyHasServicesFailure] so the screen can route the user to the
// list instead of letting them retry a guaranteed-conflict save.
//
// Built on [riverpod_generator] — never hand-construct the provider.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'service_setup_notifier.g.dart';

/// Bulk-save notifier for the first-time service-setup screen.
///
/// The [build] state is `void` and idle (no data fetched on construction — the
/// screen reads categories/service-types from the existing
/// [approvedCategoriesProvider] / `serviceTypesProvider`). Calling [submit]
/// moves the state to [AsyncLoading] for the duration of the POST, then to
/// [AsyncData] on success or [AsyncError] (carrying a typed `Failure`) on
/// failure. The screen watches this provider to drive the CTA spinner and to
/// react to the result.
///
/// Auto-disposes: the setup screen is a one-shot flow reached only from the
/// empty services list; there is no benefit to keeping the notifier alive after
/// the screen pops.
@riverpod
class ServiceSetup extends _$ServiceSetup {
  @override
  Future<void> build() async {
    // Idle initial state — nothing to load. The actual catalogue data is read by
    // the screen from the shared category / service-type providers.
  }

  /// Bulk-creates every assembled [items] row via
  /// [ServiceRepository.bulkCreate].
  ///
  /// Returns the created [MasterService] list on success (also reflected in the
  /// notifier state). On failure the state becomes [AsyncError] with the typed
  /// `Failure` and `null` is returned, so the screen can branch on the result
  /// without re-reading the error from state.
  ///
  /// [items] must be non-empty — the screen only enables the CTA when at least
  /// one service-type is included, so an empty call indicates a logic error and
  /// is short-circuited to a no-op success.
  Future<List<MasterService>?> submit(List<MasterServiceBulkItem> items) async {
    if (items.isEmpty) {
      state = const AsyncData<void>(null);
      return const <MasterService>[];
    }

    state = const AsyncLoading<void>();
    final result = await AsyncValue.guard(
      () => ref.read(serviceRepositoryProvider).bulkCreate(items),
    );

    return result.when(
      data: (created) {
        state = const AsyncData<void>(null);
        return created;
      },
      error: (error, stackTrace) {
        state = AsyncError<void>(error, stackTrace);
        return null;
      },
      loading: () => null,
    );
  }
}
