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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'working_hours_repository.dart';

part 'working_hours_repository_provider.g.dart';

/// Provides the [WorkingHoursRepository] singleton backed by the generated
/// [MasterControllerApi] and the authenticated master's Master-row UUID.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpWorkingHoursRepository] directly outside this provider and its tests.
///
/// `masterId` is read from [masterProfileProvider]; both that provider and this
/// one are [keepAlive: true]. The read path is now a network call
/// (`getWeeklySchedules`) inside the repository, so no cached week is injected —
/// the provider only needs the Master-row UUID and the API client. When the
/// profile has not resolved yet the id is `''`; the repository's
/// `_assertAuthenticated` guard converts a call into an [UnauthorizedFailure]
/// instead of a malformed-URL [NotFoundFailure].
///
/// Watches only the Master-row id via `.select` — an unrelated profile
/// invalidation (a bio or locality edit) leaves the id unchanged, so this
/// provider (and the working-hours notifier that watches it) does NOT rebuild or
/// re-fetch the week. It rebuilds only when the authenticated master's id
/// actually changes (login / logout / account switch).
@Riverpod(keepAlive: true)
WorkingHoursRepository workingHoursRepository(Ref ref) {
  final masterId = ref.watch(
    masterProfileProvider.select((async) => async.value?.id),
  );
  return HttpWorkingHoursRepository(
    masterApi: ref.watch(masterApiProvider),
    masterId: masterId ?? '',
  );
}
