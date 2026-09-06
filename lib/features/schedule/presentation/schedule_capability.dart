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
// The screen-owning master is implicitly the authenticated user. This
// resolver is still session-only — "may THIS viewer edit A schedule", not
// "may this viewer edit THAT master's schedule" — because every viewer that
// can currently reach a schedule screen only ever views their own: the
// INDEPENDENT_MASTER at `/schedule` and, since Phase 309, the SALON_MASTER
// reading the SAME `MasterScheduleScreen` read-only at `/staff/schedule`.
// Phase 311 additionally made `WeeklyTemplateEditorScreen`, `DayHoursSheet`
// and `ApplyScheduleSheet` read this provider, so it is no longer "the
// schedule screen" alone that gates on it. When salon staff/owners can view a
// SPECIFIC other master's schedule (phase-312-owner-edits-master-schedule,
// DEFERRED) this resolver will take the viewed master id and compare salon
// membership; the SALON_OWNER/SALON_ADMIN → editable rule above is already
// encoded for that path.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';

part 'schedule_capability.g.dart';

/// `true` when the current viewer may edit the schedule on screen.
///
/// Read-only resolves to `false` for SALON_MASTER (and defensively for any
/// non-master / unresolved session). Generated provider name:
/// `scheduleEditableProvider`.
///
/// Watches through [authUserRoleSettledOrNull] — the STRICT selector, not
/// [authUserRoleOrNull] (mobile-security MEDIUM, phase 309–311 track,
/// 2026-09-06). This provider is the WRITE-GATE for schedule mutation (every
/// edit affordance across `MasterScheduleScreen`,
/// `WeeklyTemplateEditorScreen`, `DayHoursSheet` and `ApplyScheduleSheet`
/// gates on it), so it must resolve read-only — not "whatever the last known
/// role was" — the instant the session is anything other than a settled,
/// authenticated `AsyncData`. A bare `.value` read (the lenient unwrap
/// [authUserRoleOrNull] deliberately uses for nav-target picks) would let a
/// STALE `Authenticated` ride a later `AsyncLoading`/`AsyncError` via
/// Riverpod's automatic `copyWithPrevious` and keep granting edit access
/// after the session it was granted for is no longer definitely valid — see
/// [authUserRoleSettledOrNull]'s doc comment for the full reasoning and why
/// the two selectors must NOT be collapsed into one.
///
/// Selecting on the role (rather than watching `authProvider` un-narrowed)
/// also keeps this provider silent across a silent token refresh —
/// `AuthNotifier.setAccessToken` emits a new `AsyncData(Authenticated(...))`
/// on every refresh (same user, new `accessToken`, which is part of
/// `Authenticated`'s `@freezed` equality) — see [authUserRoleOrNull]'s doc
/// comment (mobile-perf MEDIUM, 2026-09-06) for the measurement. Un-narrowing
/// this watch would reintroduce that churn on the four screens above.
@riverpod
bool scheduleEditable(Ref ref) {
  final role = ref.watch(authProvider.select(authUserRoleSettledOrNull));
  return switch (role) {
    UserRole.independentMaster ||
    UserRole.salonOwner ||
    UserRole.salonAdmin => true,
    UserRole.salonMaster || UserRole.client || null => false,
  };
}
