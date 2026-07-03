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

  // Phase 13.1 — CLIENT 5-tab shell branches. The CLIENT post-login landing
  // is [clientHome] (Головна, branch index 0). Each path is the location of one
  // StatefulShellRoute branch; the elevated center «Пошук» disc routes to
  // [clientSearch] (branch index 2). The 5th tab «BEAUTY PASSPORT» (an
  // untranslated brand constant) lands on [clientPassport].
  //
  // The MASTER shell keeps its own existing routes (/master/*, /services,
  // /schedule) — the two shells never share branches; role gating in
  // [authRedirect] keeps CLIENT and INDEPENDENT_MASTER mutually fenced off.
  static const String clientHome = '/home';
  static const String clientFavorites = '/favorites';
  static const String clientSearch = '/search';
  static const String clientBookings = '/bookings';
  static const String clientPassport = '/passport';

  /// Phase 13.3 — discovery results. Reached from the Пошук filters screen's
  /// «Показати майстрів» CTA via `context.push(..., extra: SearchFilters)`. A
  /// `push` (not a branch hop) so the swipe-back gesture returns to the filters
  /// with the keepAlive selection intact. The real paged results list ships in
  /// a later 13.x phase; for now the route renders a placeholder that echoes the
  /// received [SearchFilters].
  static const String clientSearchResults = '/search/results';

  /// Phase 13.5 — public master profile, opened from a master result card tap.
  /// The screen itself ships in Phase 13.5; until then the route may not be
  /// registered, but the path constant is the single source of truth for the
  /// card's nav target. Pushed onto the search branch navigator.
  static String masterPublicProfile(String masterId) =>
      '/masters/${Uri.encodeComponent(masterId)}';

  /// Phase 13.6 — public salon profile, opened from a salon result card tap.
  /// Same lifecycle note as [masterPublicProfile].
  static String salonPublicProfile(String salonId) =>
      '/salons/${Uri.encodeComponent(salonId)}';

  /// Phase 14.1 — booking flow Step 1 (service selection), opened from the
  /// public master profile's «Записатись до майстра» CTA with the
  /// target master id (a bare `String`) in `GoRouterState.extra`. Renders
  /// `ServiceSelectorSheet`, CLIENT-guarded. This constant is the single
  /// source of truth for the CTA's nav target.
  static const String bookingNew = '/booking/new';

  /// Phase 14.1 — booking flow Step 2a (date picker). Pushed from
  /// `ServiceSelectorSheet`'s «Далі» CTA with a `BookingSlotPickerArgs` in
  /// `extra`. Renders `SlotDateScreen`, CLIENT-guarded.
  static const String bookingSlots = '/booking/slots';

  /// The time sub-step of [bookingSlots], nested under it. Pushed from
  /// `SlotDateScreen`'s «Далі» CTA carrying the SAME `BookingSlotPickerArgs`
  /// — the chosen date lives in the shared `slotPickerProvider`, not in this
  /// route's extra. Renders `SlotTimeScreen`.
  static const String bookingSlotsTime = '/booking/slots/time';

  /// Phase 14.2 — booking confirmation (final review before submit). Pushed
  /// from `SlotTimeScreen`'s «Підтвердити» CTA with a `BookingConfirmArgs` in
  /// `extra`. Renders `BookingConfirmScreen`, CLIENT-guarded; a missing/
  /// wrong-typed `extra` redirects to [bookingNew] (mirrors [bookingSlots]'s
  /// guard). Replaced the Phase 14.1 `BookingConfirmPlaceholderScreen` stub
  /// at this same path.
  static const String bookingConfirm = '/booking/confirm';

  /// Phase 14.2 — booking success celebration screen. Reached ONLY via
  /// `BookingConfirmScreen`'s «Записатись» CTA `pushReplacement`ing here with
  /// a `BookingSuccessArgs` in `extra` once `POST /bookings` succeeds —
  /// REPLACING [bookingConfirm] in the nav stack (not pushing on top of it),
  /// so the confirmation screen can never be reached again via back/swipe
  /// from here. `BookingSuccessScreen` additionally wraps itself in
  /// `PopScope(canPop: false)`, fully blocking any back gesture on this
  /// screen. Between those two, there is no code path back to
  /// [bookingConfirm] — see `app_router.dart`'s route registration comment
  /// for why no extra `redirect` guard is layered on top for that specific
  /// concern. This route's OWN `redirect` only guards role + a missing/
  /// invalid `extra` (mirrors every other booking route), bouncing to
  /// [clientHome] on either.
  static const String bookingSuccess = '/booking/success';

  // Phase 14.12/14.13 — salon booking flow. A salon booking is fundamentally
  // different from the single-master flow above: the client multi-selects
  // services from the salon's FULL catalogue, then assigns each selected
  // service to one of potentially several masters (never a single
  // `masterId`), producing N appointments. These three routes are the entry
  // point for that flow, replacing the old (buggy) CTA that pushed
  // [bookingNew] with `salon.id` misused as a `masterId`.
  /// Step 1 — service selection. Pushed from the public salon profile's
  /// «Записатись на послугу» CTA with the target salon id (a bare `String`)
  /// in `GoRouterState.extra`. Renders `SalonServiceSelectionScreen`,
  /// CLIENT-guarded.
  static const String salonBookingServices = '/booking/salon/services';

  /// Step 2 — master assignment. Pushed from `SalonServiceSelectionScreen`'s
  /// «Далі» CTA with a `SalonBookingMasterSelectionArgs` in `extra`. Renders
  /// `SalonMasterSelectionScreen`, CLIENT-guarded.
  static const String salonBookingMasters = '/booking/salon/masters';

  /// Step 3 placeholder — the per-master time picker
  /// (`docs/signup-designs/SalonBookingTime/`) is deferred; this minimal
  /// stub is where «Підтвердити» on `SalonMasterSelectionScreen` routes
  /// instead, carrying the salon id (a bare `String`) in `extra` so the
  /// placeholder can offer a "back to profile" action. Never routes into the
  /// independent-master `SlotPickerScreen` — that flow assumes one master,
  /// not the salon's N-appointments-per-master model.
  static const String salonBookingComingSoon = '/booking/salon/coming-soon';

  // CLIENT settings hub + per-section edit pages. Pushed from the home-hub
  // burger icon (mirrors the master `/master/menu` + `/master/edit/*` block).
  // The three edit pages all PATCH /users/me via ClientProfileRepository,
  // merging only the slice they own onto the cached profile so sibling fields
  // are never cleared. Role-gated to CLIENT in [authRedirect].
  static const String clientMenu = '/client/menu';
  static const String clientEditPersonal = '/client/edit/personal';
  static const String clientEditContacts = '/client/edit/contacts';
  static const String clientEditLocation = '/client/edit/location';

  /// Support / contact-us screen («Напишіть нам»). Pushed from the master
  /// settings hub's "Допомога / Напишіть нам" row. Authenticated users submit a
  /// free-text message (+ optional subject + attachments) to
  /// `POST /api/v1/support/contact`.
  static const String contactSupport = '/support/contact';

  // Phase 4.2 — Master profile (read-only).
  static const String masterProfile = '/master/profile';

  // Master profile settings hub (INDEPENDENT_MASTER). Pushed from the profile
  // screen's top-right menu icon. Lists edit sections, each pushing its own
  // dedicated page; the terminal logout row raises the logout confirm dialog.
  static const String masterMenu = '/master/menu';

  // Master profile section edit pages — each edits one slice of the profile.
  // Personal-info and Contacts both call updateMyProfile (merging onto the
  // cached master so sibling fields are never cleared); Location calls
  // updateLocality. The old monolithic /master/edit form they replace is
  // retired.
  static const String masterEditPersonal = '/master/edit/personal';
  static const String masterEditContacts = '/master/edit/contacts';
  static const String masterEditLocation = '/master/edit/location';

  // Phase 5.2 — Service catalogue (INDEPENDENT_MASTER).
  static const String services = '/services';
  static const String serviceCreate = '/services/create';
  static String serviceEdit(String id) => '/services/$id/edit';

  /// First-time service setup (INDEPENDENT_MASTER). The empty-state, one-pass
  /// menu builder reached from the services-list empty state when the master
  /// has zero services. Saves via `POST /independent-masters/me/services/bulk`.
  static const String serviceSetup = '/services/setup';

  // Phase 6.2 — legacy working-hours editor path. The route is NO LONGER
  // registered in [app_router] (it was orphaned + deep-link-reachable, writing
  // the deprecated `working_hours` table; the live edit path is
  // [scheduleWeeklyEditor]). The constant is retained ONLY because the SEC
  // role-gate regression tests in auth_redirect_test.dart use it as a
  // representative `/master/*` location to pin the prefix guard. Do not wire a
  // GoRoute back onto it.
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

  // Phase 13.7 (revised) — CLIENT rating screen.
  //   • /rating — CLIENT's aggregate two-sided rating (★ n.n or empty).
  //     Backend GET /clients/me/rating is not yet shipped; the screen shows
  //     the empty state. Client comments are never shown (two-sided ratings only).
  static const String myRating = '/rating';
}
