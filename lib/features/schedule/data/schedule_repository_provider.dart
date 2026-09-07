// Phase 15.1 — Riverpod provider for [ScheduleRepository].
//
// Phase 312 — became a FAMILY keyed on [ScheduleScope] and DROPPED its
// [masterProfileProvider] watch entirely. That watch was the 403 hazard the
// phase 312 brief calls out: a SALON_OWNER/SALON_ADMIN viewing another
// master's schedule must never resolve THEIR OWN "me" profile — and
// `GET /masters/me` outright refuses a SALON_ADMIN session
// (`MasterController.java:109`), so the old unconditional watch would 403 the
// instant an admin reached this provider. [ScheduleScope.masterId] is now the
// ONLY id this provider ever reads — for [ScheduleScope.own] that id is
// resolved upstream, by `own_schedule_scope.dart`'s `ownScheduleScopeProvider`
// (which performs the SAME "me" resolution this provider used to do inline,
// but ONLY for the two roles that genuinely have their own master row); for
// [ScheduleScope.salonMaster] it is the viewed master's row id, resolved from
// the salon roster (`salonStaffMemberProfileProvider`).
//
// Kept in its own file (separate from the repository) so the repository stays
// a pure, provider-free unit that tests can construct directly with a
// mocktail [MasterControllerApi]. Mirrors the working-hours / services
// features' long-standing split.
//
// `masterId` empty (unresolved [ScheduleScope.own], or a scope this session
// could never legitimately construct) → every method short-circuits to
// [UnauthorizedFailure] via the repository's `_assertAuthenticated` guard,
// unchanged from before this phase.

import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/schedule_scope.dart';
import 'schedule_repository.dart';

part 'schedule_repository_provider.g.dart';

/// Provides the [ScheduleRepository] for [scope], backed by the generated
/// [MasterControllerApi] and [ScheduleScope.masterId].
///
/// Override in tests with a mocktail mock — never construct
/// [HttpScheduleRepository] directly outside this provider and its tests.
///
/// Generated provider name: `scheduleRepositoryProvider` (a family — call
/// `scheduleRepositoryProvider(scope)`).
@Riverpod(keepAlive: true)
ScheduleRepository scheduleRepository(Ref ref, ScheduleScope scope) {
  return HttpScheduleRepository(
    masterApi: ref.watch(masterApiProvider),
    masterId: scope.masterId,
  );
}
