// Phase 6.1 — Riverpod provider for [WorkingHoursRepository].
//
// Resolves the Master-row UUID from [masterProfileProvider] (NOT the User UUID
// from the auth session — they differ) and injects it plus the generated
// [MasterControllerApi] into [HttpWorkingHoursRepository].
//
// Kept in its own file (separate from the repository) so the repository stays a
// pure, provider-free unit that tests can construct directly with a mocktail
// [MasterControllerApi]. Mirrors the services feature's provider split.

import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'working_hours_repository.dart';

part 'working_hours_repository_provider.g.dart';

/// Provides the [WorkingHoursRepository] singleton backed by the generated
/// [MasterControllerApi] and the authenticated master's Master-row UUID.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpWorkingHoursRepository] directly outside this provider and its tests.
///
/// Both `masterId` and the read-path `cachedWeek` are read from
/// [masterProfileProvider]; both that provider and this one are
/// [keepAlive: true]. The watch is reactive on purpose (PERF M2): when the
/// profile is invalidated (profile edit, locality change, or a working-hours
/// save) this provider rebuilds with the fresh cached week, so the repository
/// never serves a stale read. When the profile has not resolved yet the id is
/// `''` and the week is empty; the repository's `_assertAuthenticated` guard
/// converts a write attempt into an [UnauthorizedFailure] instead of a
/// malformed-URL [NotFoundFailure].
@Riverpod(keepAlive: true)
WorkingHoursRepository workingHoursRepository(Ref ref) {
  final master = ref.watch(masterProfileProvider).value;
  return HttpWorkingHoursRepository(
    masterApi: ref.watch(masterApiProvider),
    masterId: master?.id ?? '',
    cachedWeek: master?.workingHours ?? const [],
  );
}
