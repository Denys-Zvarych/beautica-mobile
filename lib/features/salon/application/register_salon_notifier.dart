// Phase 21.3 — Register New Salon notifier.
//
// Backing notifier for `RegisterSalonScreen`: a `SALON_OWNER` adding another
// salon under their account. Unlike `SalonManagementProfile` (which LOADS an
// existing salon before it can be edited), there is nothing to load here —
// `build()` is a no-op; the notifier exists purely to own [submit] and its
// `ref` (for `mySalonsProvider` invalidation) outside the widget tree, mirroring
// `SalonManagementProfile.save`/`.saveAddress`/`.deleteSalon`'s own
// `Future<Failure?>` mutate-method shape rather than inventing a different
// convention.
//
// REUSE-FIRST — no new write path: [submit] wraps the EXISTING
// `SalonRepository.create` verbatim (`salon_repository.dart:141`/`:249`).
//
// CRITICAL fix (mobile-qa `register_salon_flow_test.dart`, real-backend
// round trip) — this provider is a plain (autoDispose) `@riverpod`
// provider; `RegisterSalonScreen` used to only ever `ref.read` its
// `.notifier`, never `ref.watch` it, so nothing kept its element alive
// across the `await` in [submit]. Against a synchronous fake repository
// the race never opened, but against a real Dio round trip Riverpod
// disposed the element WHILE `POST /salons` was still in flight, so the
// post-await `ref.invalidate(mySalonsProvider)` below fired on a dead
// `ref` and threw `UnmountedRefException` on every real submit.
// `RegisterSalonScreen.build()` now `ref.watch(registerSalonProvider)`s
// this provider for its whole lifetime (see that screen's own doc) —
// the fix lives on the WATCHING side, not here, so [submit]'s own shape
// (and its co-located `mySalonsProvider` invalidation, which
// `test/core/provider_cycle_guard_test.dart`'s bare
// `registerSalonProvider.notifier.submit()` entrypoint still exercises
// with no screen involved) is unchanged.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../data/salon_repository.dart';
import 'my_salons_notifier.dart';

part 'register_salon_notifier.g.dart';

/// Drives the `RegisterSalonScreen` submit — creates a salon via
/// `POST /salons` and keeps the «Мої салони» hub's cached list in sync.
///
/// Generated provider name: `registerSalonProvider`.
@riverpod
class RegisterSalon extends _$RegisterSalon {
  @override
  void build() {}

  /// Creates the salon via [SalonRepository.create]. On success, invalidates
  /// [mySalonsProvider] so the «Мої салони» hub refetches and shows the new
  /// salon WITHOUT a manual refresh — mirrors [SalonManagementProfile.save]/
  /// `.saveAddress`/`.deleteSalon`'s identical invalidation (mobile-perf
  /// MEDIUM follow-up, Phase 21.2/21.10 — `mySalonsProvider` is a
  /// `@Riverpod(keepAlive: true)` singleton, so nothing else would ever
  /// refetch it once the owner has visited the hub once this session).
  ///
  /// cycle-safe: `mySalonsProvider` (`MySalons.build()`) only watches
  /// `authProvider` — it never watches `registerSalonProvider`, so there is
  /// no back-edge here to close into a cycle (same note
  /// `SalonManagementProfile`'s own mutate methods carry).
  ///
  /// Returns `null` on success or the [Failure] on error.
  Future<Failure?> submit({
    required String name,
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
    String? phone,
    String? instagramUrl,
  }) async {
    try {
      await ref
          .read(salonRepositoryProvider)
          .create(
            dto: SalonCreateDto(
              name: name,
              cityId: cityId,
              districtId: districtId,
              street: street,
              buildingNo: buildingNo,
              locationNote: locationNote,
              phone: phone,
              instagramUrl: instagramUrl,
            ),
          );
      // cycle-safe: mySalonsProvider (MySalons.build()) only watches
      // authProvider — it never watches registerSalonProvider (this
      // notifier's own provider), so there is no back-edge here to close
      // into a cycle. See this file's header doc for why this invalidation
      // exists: keeps the «Мої салони» hub's cached list from going stale
      // after a create. Runtime-proven on the real provider graph by
      // `test/core/provider_cycle_guard_test.dart`'s own
      // `registerSalonProvider.notifier.submit()` entrypoint.
      ref.invalidate(mySalonsProvider);
      return null;
    } on Failure catch (f) {
      return f;
    }
  }
}
