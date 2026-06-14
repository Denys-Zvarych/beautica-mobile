// Phase 15.2 — Schedule edit-capability resolver (OQ-2 role gating).
//
// Resolves whether the current viewer may EDIT the schedule they are viewing,
// from the auth/role state. The schedule screen gates every edit affordance
// (Редагувати, day pencil, + Додати час, + Time Off, copy/propagate, and the
// NO_SCHEDULE CTA) on this capability so a read-only role never sees an edit
// entry point — client-side, not relying on a backend 403 alone.
//
// MVP scope (ARCHITECTURE-mobile § 4 — INDEPENDENT_MASTER first):
//   • INDEPENDENT_MASTER (viewing own schedule)            → editable.
//   • SALON_OWNER / SALON_ADMIN (their salon's master)     → editable.
//   • SALON_MASTER (viewing own schedule, read-only role)  → read-only.
//   • CLIENT / loading / unauthenticated                   → read-only
//     (defensive: a CLIENT never reaches this screen, but defaulting to
//     read-only keeps the gate fail-safe).
//
// The screen-owning master is implicitly the authenticated user (the only
// schedule surface in MVP is the master's own). When salon staff can view a
// specific master's schedule (later phase) this resolver will take the viewed
// master id and compare salon membership; the SALON_OWNER/SALON_ADMIN → editable
// rule above is already encoded for that path.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';

part 'schedule_capability.g.dart';

/// `true` when the current viewer may edit the schedule on screen.
///
/// Read-only resolves to `false` for SALON_MASTER (and defensively for any
/// non-master / unresolved session). Generated provider name:
/// `scheduleEditableProvider`.
@riverpod
bool scheduleEditable(Ref ref) {
  final session = ref.watch(authProvider).value;
  if (session is! Authenticated) return false;
  return switch (session.user.role) {
    UserRole.independentMaster ||
    UserRole.salonOwner ||
    UserRole.salonAdmin => true,
    UserRole.salonMaster || UserRole.client => false,
  };
}
