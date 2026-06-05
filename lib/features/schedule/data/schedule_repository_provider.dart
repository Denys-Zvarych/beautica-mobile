// Phase 15.1 — Riverpod provider for [ScheduleRepository].
//
// Resolves the Master-row UUID from [masterProfileProvider] (NOT the User UUID
// from the auth session — they differ) and injects it plus the generated
// [MasterControllerApi] into [HttpScheduleRepository].
//
// Kept in its own file (separate from the repository) so the repository stays a
// pure, provider-free unit that tests can construct directly with a mocktail
// [MasterControllerApi]. Mirrors the working-hours / services feature splits.
//
// The `masterId` watch is reactive on purpose: when the profile is invalidated
// the repository rebuilds with the fresh id. While the profile is unresolved
// the id is `''` and every method short-circuits to [UnauthorizedFailure] via
// the repository's `_assertAuthenticated` guard.

import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'schedule_repository.dart';

part 'schedule_repository_provider.g.dart';

/// Provides the [ScheduleRepository] singleton backed by the generated
/// [MasterControllerApi] and the authenticated master's Master-row UUID.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpScheduleRepository] directly outside this provider and its tests.
@Riverpod(keepAlive: true)
ScheduleRepository scheduleRepository(Ref ref) {
  final master = ref.watch(masterProfileProvider).value;
  return HttpScheduleRepository(
    masterApi: ref.watch(masterApiProvider),
    masterId: master?.id ?? '',
  );
}
