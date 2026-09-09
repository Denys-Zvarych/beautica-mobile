// Phase 314 — ServiceTarget: the services surface's retarget seam.
//
// The locked product decision for the salon-owned-master-services track is
// TOTAL REUSE: a salon master's services surface IS the independent master's
// services surface — the same `ServicesListScreen`, `ServiceSetupScreen`,
// `ServiceEditScreen`, `ServiceCard` and `DeleteServiceDialog`. No fork, no
// `*_variant.dart`, no bespoke per-master UI.
//
// That works because all three screens funnel every read and every write
// through `serviceRepositoryProvider`. [ServiceTarget] is the one scoped value
// that says WHOSE services that repository is operating on; phases 315/316
// dispatch the actual paths on it, and phase 317 is the only place that ever
// constructs a non-null one (inside a `ProviderScope` wrapping the salon-target
// route subtree, so the scope unwinds on pop).
//
// WHY @freezed AND NOT A PLAIN SEALED CLASS (supersedes the phase doc's D1).
// D1 originally specified a plain `sealed class` with two `final String`
// fields — i.e. identity equality. A perf HIGH reversed that: this type is the
// value of `serviceTargetProvider`, and riverpod gates dependent rebuilds on
// `!=` (`riverpod-3.1.0/lib/src/providers/provider.dart:349`, and
// `core/override_with_value.dart:78` for the `overrideWithValue` path). Under
// identity equality a `ProviderScope` that rebuilds and hands down a FRESH
// target carrying the SAME two ids tears down and re-creates
// `serviceRepositoryProvider` — `keepAlive: true`, read from a dozen call
// sites, two of whose watchers (`services_list_notifier.dart:34`,
// `master_service_catalog_provider.dart:125`) fire `listMyServices()`
// unconditionally in `build()`. From phase 317 that is two GETs and an
// `AsyncLoading` spinner flash per ancestor rebuild, for no semantic change.
//
// `ScheduleScope` — this track's exact analogue, the viewer-scope union of the
// schedule feature — is `@freezed` for precisely this reason
// (`lib/features/schedule/domain/schedule_scope.dart:33`). This file mirrors
// it, private `const ServiceTarget._();` constructor included, so the sealed
// shape and the exhaustive `switch` in `_assertAuthenticated` survive.
// Do NOT "restore" the plain class: the equality is load-bearing and is pinned
// by `test/features/services/domain/service_target_test.dart`.
//
// This file is pure Dart — no Flutter import — per the domain-layer rule.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'service_target.freezed.dart';

/// Whose services the services surface is operating on.
///
/// `null` (the default of `serviceTargetProvider`) means the authenticated
/// INDEPENDENT_MASTER's own services — which is what every shipped call site
/// means today. A sealed type is used deliberately over a loose pair of
/// nullable strings: two nullable fields admit three illegal states (salon
/// without master, master without salon, and the half-constructed case a
/// `?? ''` fallback produces silently), whereas
/// `switch (target) { null => …, SalonMasterTarget t => … }` is exhaustive, so
/// every future repository path is forced to say what it does in salon mode.
@freezed
sealed class ServiceTarget with _$ServiceTarget {
  /// A named master inside a salon, driven by that salon's OWNER or ADMIN.
  ///
  /// [SalonMasterTarget.masterId] is the backend `masters` ROW id — **NOT a
  /// userId**. Passing a userId to any
  /// `/salons/{salonId}/masters/{masterId}/...` path yields
  /// `404 Master not found`, not `403`. This is the same warning
  /// `serviceRepositoryProvider` already carries about its own `masterId`
  /// (`service_repository.dart` — "the Master-row UUID from
  /// MasterDetailResponse.masterId, NOT the User UUID from the auth session;
  /// User.id != Master.id"). The userId → masterId resolution happens in phase
  /// 317, mirroring `_SalonMasterScheduleRoute`.
  ///
  /// Deliberately carries no `priceOverride` / `durationOverrideMinutes`: the
  /// backend's `AssignServiceToMasterRequest` has both, but mobile ignores them
  /// entirely by locked decision — one salon definition, one price, shared
  /// across every master who performs it.
  const factory ServiceTarget.salonMaster({
    /// The salon whose roster `masterId` sits on.
    required String salonId,

    /// The backend `masters` ROW id — NOT a userId. See the factory doc.
    required String masterId,
  }) = SalonMasterTarget;

  const ServiceTarget._();
}
