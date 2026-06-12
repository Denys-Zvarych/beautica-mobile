/// Route path constants for `go_router`.
///
/// Raw path strings must never appear elsewhere in `lib/` — always reference
/// this class so renaming a route is a single-point change.
abstract final class RouteNames {
  static const String splash = '/splash';
  static const String login = '/login';

  // Phase 2.16 — multi-step registration wizard. The three /register* paths
  // share a `RegisterFlowShell` chrome (status bar + brand row + role chip +
  // 4-pill progress + glass card) via a `ShellRoute`.
  /// Pre-wizard role-selection gate. The chosen role is written into the
  /// `registerDraftProvider` before the user advances to `/register`.
  static const String registerRole = '/register/role';

  /// Step 1 — credentials (email + password + confirm-password). Phase 2.16.
  static const String register = '/register';

  /// Step 2 — profile (name + surname + phone + salonName). Phase 2.17.
  static const String registerStep2 = '/register/step-2';

  /// Step 3 — address (oblast/city/district + street/building/note). Phase 2.19.
  static const String registerStep3 = '/register/step-3';

  // Phase 2.13 — forgot-password flow.
  /// Step 1 — request a reset link by email (anti-enumeration confirmation).
  static const String forgotPassword = '/forgot-password';

  /// Step 2 — set a new password. The single-use reset token arrives as the
  /// `token` query parameter (matching the backend deep-link contract
  /// `/reset-password?token=...`), never typed by the user. Reached from the
  /// emailed deep link; full deep-link wiring is deferred to a later phase
  /// (see phase doc), but the route already parses the query param so the
  /// link works the moment app-link handling is registered.
  static const String resetPassword = '/reset-password';

  // Phase 2.20 — accept-invite deep link. The invite token arrives as the
  // `token` query parameter from the emailed link (`/invite/accept?token=...`).
  // Unauthenticated users may land here directly; the router guard allows it.
  static const String acceptInvite = '/invite/accept';

  // Phase 2.11 — email verification; receives email via GoRouterState.extra.
  static const String verification = '/verification';
  // Phase 2.12 — registration done screen (placeholder: redirects to home).
  static const String done = '/done';
  static const String home = '/';
  static const String settings = '/settings';

  // Phase 4.2 — Master profile (read-only).
  static const String masterProfile = '/master/profile';

  // Phase 4.3 — Master profile edit form (INDEPENDENT_MASTER only).
  static const String masterEdit = '/master/edit';

  // Phase 5.2 — Service catalogue (INDEPENDENT_MASTER).
  static const String services = '/services';
  static const String serviceCreate = '/services/create';
  static String serviceEdit(String id) => '/services/$id/edit';

  /// First-time service setup (INDEPENDENT_MASTER). The empty-state, one-pass
  /// menu builder reached from the services-list empty state when the master
  /// has zero services. Saves via `POST /independent-masters/me/services/bulk`.
  static const String serviceSetup = '/services/setup';

  // Phase 6.2 — Working hours editor (INDEPENDENT_MASTER). Still reachable as a
  // sub-editor of the schedule; the Календар nav tile now opens [masterSchedule].
  static const String workingHours = '/master/working-hours';

  // Phase 15.2 — Master schedule («Графік роботи»). The destination of the
  // Календар bottom-nav tile: a calendar-first availability view (read path).
  static const String masterSchedule = '/schedule';

  // Phase 15.5 — the weekly-template editor («Робочі дні та години»). The
  // schedule screen's empty-state CTA and «Редагувати» affordance route here;
  // the editor saves via the `weekly-schedules` data path (the one the calendar
  // reads) — NOT the deprecated `working_hours` editor at [workingHours].
  static const String scheduleWeeklyEditor = '/schedule/weekly';

  // Phase 15.2 — routed editor stubs (real placeholder screens until the
  // corresponding phase lands; they replace these at the same paths):
  //   • 15.4 — per-date override sheet (day pencil / + Додати час / + Time Off)
  //   • 15.5 — copy/propagate range surface
  static const String scheduleDayOverride = '/schedule/day';
  static const String schedulePropagate = '/schedule/copy';
}
