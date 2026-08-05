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

  // Phase 2.13 — forgot-password flow. Beautica OTP task (Phase B) replaced
  // the emailed reset-link with a 6-digit OTP code, mirroring the
  // registration email-verification pattern.
  /// Step 1 — request a reset OTP by email (anti-enumeration confirmation).
  static const String forgotPassword = '/forgot-password';

  /// Step 2 — the generalized password-reset OTP screen
  /// ([ResetOtpVerificationScreen]) for the UNAUTHENTICATED forgot-password
  /// flow. Reached from [ForgotPasswordRequestScreen] with the submitted
  /// email (a bare `String`) in `GoRouterState.extra`.
  ///
  /// The AUTHENTICATED settings change-password flow reaches the SAME
  /// [ResetOtpVerificationScreen] widget via the separate [changePassword]
  /// route below instead (no email extra needed — the caller's identity
  /// comes from the session) — see `app_router.dart` for both registrations.
  static const String resetOtpVerification = '/reset-password/otp';

  /// Step 3 — set a new password. The single-use reset ticket (minted by
  /// `POST /auth/verify-password-reset-otp`) arrives via in-app navigation as
  /// a [ResetPasswordArgs] in `GoRouterState.extra` — NOT a `?token=` query
  /// parameter anymore (there is no more emailed link to deep-link from).
  static const String resetPassword = '/reset-password';

  /// Authenticated "change password" entry point, reached from the account
  /// settings screen's "Змінити пароль" row. Renders the SAME
  /// [ResetOtpVerificationScreen] as [resetOtpVerification] but binds its
  /// closures to the authenticated `requestChangePasswordOtp` /
  /// `verifyPasswordResetOtp` calls instead — see `app_router.dart`.
  static const String changePassword = '/settings/change-password';

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

  /// Phase 14.3 — «Деталі запису», nested under [clientBookings] so it
  /// pushes onto that branch's own navigator (swipe-back returns to the
  /// still-scrolled list). Reached by tapping any `BookingCard`.
  static String bookingDetail(String bookingId) =>
      '$clientBookings/${Uri.encodeComponent(bookingId)}';

  /// Phase 14.6 — «ВІДГУК ПРО МАЙСТРА» (leave-review), nested under
  /// [bookingDetail] so it pushes onto the Записи branch's own navigator. It is
  /// BOTH the detail screen's `canReview` entry target AND the backend 18.5
  /// `reviewUrl` push deep-link target. CLIENT-only via the `/bookings` prefix
  /// gate in [authRedirect].
  static String bookingReview(String bookingId) =>
      '$clientBookings/${Uri.encodeComponent(bookingId)}/review';

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

  /// Phase 4.x — public master reviews, opened from the public master
  /// profile's «Відгуки» stat tile. CLIENT-guarded like [masterPublicProfile]
  /// (same `clientOnlyGuard` in `app_router.dart`). Distinct from
  /// [masterReceivedReviews] below, which is param-less and always resolves
  /// to the AUTHENTICATED master's own reviews.
  static String masterPublicReviews(String masterId) =>
      '/masters/${Uri.encodeComponent(masterId)}/reviews';

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

  /// Step 3 — single date/time picker ("Час"), MO-4. Pushed from
  /// `SalonMasterSelectionScreen`'s «Далі» CTA with a `SalonBookingTimeArgs`
  /// (the resolved single-master visit) in `extra`. Renders `SalonTimeScreen`,
  /// CLIENT-guarded. (The pre-MO-4 `/booking/salon/coming-soon` placeholder
  /// route is retired.)
  static const String salonBookingTime = '/booking/salon/time';

  /// Step 4 — salon booking confirmation (review + submit), MO-4. Pushed from
  /// `SalonTimeScreen`'s «Далі» CTA with a `SalonBookingConfirmArgs` (the
  /// single resolved visit) in `extra`. Renders `SalonBookingConfirmScreen`,
  /// CLIENT-guarded; submits ONE `POST /appointments` via the shared
  /// `AppointmentSubmit`.
  static const String salonBookingConfirm = '/booking/salon/confirm';

  /// Step 4b — salon booking success recap, MO-4. Reached ONLY via
  /// `SalonBookingConfirmScreen`'s `pushReplacement` once the single
  /// `POST /appointments` succeeded, carrying a `SalonBookingSuccessArgs` in
  /// `extra`.
  /// Renders `SalonBookingSuccessScreen` (`PopScope(canPop: false)`),
  /// CLIENT-guarded; a missing/invalid `extra` bounces to [clientHome].
  static const String salonBookingSuccess = '/booking/salon/success';

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

  /// Phase 7.6 — the independent master's «Мої записи», the destination of the
  /// master bottom-nav tab at index 1 (which had no route until this phase).
  ///
  /// ## Deliberately NOT [clientBookings] (`/bookings`)
  ///
  /// `/bookings` is the CLIENT «Мої записи» (Phase 14.3). It lives inside the
  /// client `StatefulShellRoute` branch and is gated CLIENT-only by
  /// `authRedirect`'s prefix rules — sending a master there would put them
  /// inside the client shell (client bottom nav, client guard) looking at a
  /// list built from the client's own query. The two screens share a NAME and
  /// nothing else: different provider, different query object, different card,
  /// different perspective.
  static const String masterBookings = '/master/bookings';

  /// Phase 7.2 — the provider view of one booking, pushed from a
  /// [masterBookings] card tap.
  ///
  /// A CHILD of [masterBookings], so it pushes onto the master's own stack and
  /// pops back to the still-scrolled list. It resolves to the SAME
  /// `BookingDetailScreen` as [bookingDetail] — one screen, role-branched
  /// (locked decision D5) — but it must keep its own path for the same
  /// shell/guard reason [masterBookings] does.
  ///
  /// Navigate with `context.push`. Note the go_router gotcha: a pushed route
  /// yields an `ImperativeRouteMatch` that go_router drops from
  /// `currentConfiguration.fullPath`, so this path reads as its PARENT
  /// (`/master/bookings`) to any nav-detection logic — inspect
  /// `leaf.matches.fullPath` instead.
  static String masterBookingDetail(String bookingId) =>
      '$masterBookings/${Uri.encodeComponent(bookingId)}';

  /// Track 7.x Wave B — «ВІДГУК ПРО КЛІЄНТА» (leave-client-feedback), nested
  /// under [masterBookingDetail] so it pushes onto the master's own stack and
  /// pops back to the detail — mirrors [bookingReview]'s nesting for the
  /// opposite (CLIENT→MASTER) direction.
  ///
  /// Reached from the detail's COMPLETED-provider-booking entry CTA
  /// (`_DetailBody._providerActions`). Unlike [bookingReview] there is no
  /// server-computed canReview-equivalent flag for the provider side yet, so
  /// the CTA is offered on every COMPLETED provider booking; a duplicate
  /// submit's 409 is handled ON the destination screen (see
  /// `LeaveClientFeedbackScreen`'s file header).
  static String clientReview(String bookingId) =>
      '${masterBookingDetail(bookingId)}/review';

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

  // Phase 4.6 — Master received-reviews screen («Мої відгуки»). Pushed from the
  // master profile's "Відгуки" stat tile. Param-less: the screen reads its own
  // masterId from the session (authProvider), so the reviews are always the
  // authenticated master's own.
  static const String masterReceivedReviews = '/master/received-reviews';

  // Phase 5.2 — Service catalogue (INDEPENDENT_MASTER).
  static const String services = '/services';
  static String serviceEdit(String id) => '/services/$id/edit';

  /// Service setup (INDEPENDENT_MASTER) — the ONE "add services" surface.
  ///
  /// The multi-select menu builder, reached from BOTH the services-list empty
  /// state and the «Додати послугу» FAB on a populated list. Saves via
  /// `POST /independent-masters/me/services/bulk`, which the backend made
  /// additive (`beautica-backend` c5e420f) — so it appends to an existing
  /// catalogue just as well as it seeds an empty one.
  ///
  /// The former single-create form (`/services/create`) was removed when the
  /// two flows were collapsed onto this screen; do not reintroduce it.
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
