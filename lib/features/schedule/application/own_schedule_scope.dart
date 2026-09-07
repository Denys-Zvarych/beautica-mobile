// Phase 312 — resolves the CALLER's own [ScheduleScope] ("me").
//
// Every schedule screen/editor's additive `scope` param defaults to `null`,
// which resolves through THIS provider (`master_schedule_screen.dart` and the
// three editors: `widget.scope ?? ref.watch(ownScheduleScopeProvider)`) — so
// the ordering below is the actual fix for the SALON_ADMIN 403 phase 312's
// brief calls out, not merely documentation of it.
//
// THE PIN: the role check runs FIRST, before this ever watches
// [masterProfileProvider]. `GET /masters/me` is gated
// `hasAnyRole('SALON_MASTER', 'INDEPENDENT_MASTER', 'SALON_OWNER')`
// (`MasterController.java:109`) — a SALON_ADMIN has NO master row and would
// 403 the instant this watched it. Mutation #6 (this phase) proves the
// ordering: moving the role check AFTER the profile watch must make
// `verifyNever(getMe)` fire for an admin session.
//
// SALON_OWNER is deliberately REFUSED here too, even though `GET /masters/me`
// itself admits that role server-side — OQ-4, ACCEPTED as designed: no
// owner-operated-as-a-master surface exists today
// (`project_owner_as_master_multisalon_blocked` is the upstream block), so
// this provider never resolves an owner's "own" schedule. Only
// INDEPENDENT_MASTER and SALON_MASTER (phase 309's read-only self-view) ever
// have a real "own" master row reachable through a schedule screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../master/presentation/master_profile_notifier.dart';
import '../domain/schedule_scope.dart';

part 'own_schedule_scope.g.dart';

/// The current viewer's own [ScheduleScope.own] — `masterId` is `''` for
/// every role this deliberately refuses to resolve (see this file's header),
/// which every downstream repository already treats as "unauthenticated" and
/// fails closed on (`UnauthorizedFailure`).
@riverpod
ScheduleScope ownScheduleScope(Ref ref) {
  // Narrowed selector (not a bare `ref.watch(authProvider)`), same reasoning
  // as `master_schedule_screen.dart`'s `profileRoute` resolution — the role
  // is stable across a silent token refresh, so this stays silent through
  // one too.
  final UserRole? role = ref.watch(authProvider.select(authUserRoleOrNull));

  // THE PIN — this check runs BEFORE touching `masterProfileProvider` at
  // all. Only these two roles ever have their own master row reachable this
  // way; every other role (SALON_OWNER, SALON_ADMIN, CLIENT, unresolved)
  // returns immediately with no watch of `masterProfileProvider` — so an
  // admin session can never reach `GET /masters/me` through this path.
  final bool hasOwnMasterRow =
      role == UserRole.independentMaster || role == UserRole.salonMaster;
  if (!hasOwnMasterRow) {
    return const ScheduleScope.own(masterId: '');
  }

  final master = ref.watch(masterProfileProvider).value;
  return ScheduleScope.own(masterId: master?.id ?? '');
}
