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

  /// Phase 239 — «Усі збережені», the full BEAUTY WISH LIST. Nested under
  /// [clientPassport] so it pushes onto the passport branch's OWN navigator:
  /// swipe-back then returns to the still-scrolled passport page instead of
  /// unwinding to a branch root.
  ///
  /// ⚠ Reached with `context.push`, never `context.go`. A pushed leaf collapses
  /// to the PARENT path in `GoRouterState.fullPath`, so a `go`-based navigation
  /// test would false-pass against `/passport`.
  static const String clientWishlist = '$clientPassport/wishlist';

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
  ///
  /// Bare path only. An earlier cut accepted an optional `serviceId` that
  /// appended `?serviceId=<id>&tab=masters`, deep-linking the profile's
  /// "Майстри" tab pre-filtered to one service for the salon-arm wish-list
  /// CTA. That CTA now re-enters the salon booking flow's step-2 master picker
  /// ([salonBookingMasters]) instead — a screen that already IS "the salon's
  /// masters who perform the selected service(s)" — so the parameter, its
  /// query assembly and the screen-side seed were all deleted as redundant.
  /// The in-profile service→masters filter reachable by TAPPING a service in
  /// the "Послуги" tab is a separate, unaffected feature.
  static String salonPublicProfile(String salonId) =>
      '/salons/${Uri.encodeComponent(salonId)}';

  /// Phase 21.2 — owner/admin editable salon profile (structurally a mirror
  /// of [salonPublicProfile], with edit/staff-management/delete affordances
  /// layered on top). `SALON_OWNER` (any owned salon) / `SALON_ADMIN` (their
  /// own salon only) — gated in `app_router.dart` via `_salonManageGuard`,
  /// mirroring the `/master/*`/`/salon/*` prefix-gate convention in
  /// `auth_redirect.dart` (this route sits under `/salons/:salonId/manage`,
  /// a NESTED child of [salonPublicProfile]'s own literal-path segment, not
  /// the `/salon/*` prefix those gates cover, so it needs its own).
  static String salonManage(String salonId) =>
      '${salonPublicProfile(salonId)}/manage';

  /// Phase 21.2 — the salon settings page the management profile's top-right
  /// `Icons.tune_rounded` cover control opens. Two rows only: «Редагувати
  /// профіль» (nav — pops back to [salonManage] with edit mode toggled on)
  /// and, owner-only, the destructive «Видалити салон». Phase 21.9 later
  /// supersedes this 2-row page with a full multi-row settings hub (mirroring
  /// the preview's `salon_settings_screen.dart`) — that phase EXTENDS this
  /// route/screen rather than replacing it outright, so the path is not
  /// versioned or phase-suffixed.
  static String salonManageSettings(String salonId) =>
      '${salonManage(salonId)}/settings';

  /// Phase 21.10 — dedicated «Назва та опис» edit screen (name +
  /// description), reached from the Phase 21.9 settings hub's own
  /// navigational row. A literal child of [salonManageSettings], gated by the
  /// SAME `salonManageGuard` (registered as a standalone top-level route in
  /// `app_router.dart`, mirroring [salonManage]/[salonManageSettings]'s own
  /// "an ancestor's own redirect always runs" rationale). No in-app entry
  /// point exists yet — Phase 21.9 (the settings hub) is what wires a row to
  /// this route; that phase is unbuilt.
  static String salonProfileEdit(String salonId) =>
      '${salonManageSettings(salonId)}/profile-edit';

  /// Phase 21.10 — dedicated «Локація» edit screen (locality cascade +
  /// street/buildingNo/locationNote). Sibling of [salonProfileEdit] — same
  /// gating, same "no entry point yet" caveat.
  static String salonAddressEdit(String salonId) =>
      '${salonManageSettings(salonId)}/address-edit';

  /// Phase 21.10 — dedicated «Контакти» edit screen (phone + Instagram).
  /// Sibling of [salonProfileEdit] — same gating, same "no entry point yet"
  /// caveat.
  static String salonContactsEdit(String salonId) =>
      '${salonManageSettings(salonId)}/contacts-edit';

  /// Phase 21.8 — the SHARED `SALON_OWNER`/`SALON_ADMIN` landing
  /// (`roleHomePath`), rendering [SalonHomeResolverScreen]. A transient
  /// stopover, not a destination the viewer lingers on: it resolves which
  /// salon's shell ([salonShell]) to enter and forwards there (a
  /// `SALON_ADMIN` reads `session.user.salonId` synchronously; a
  /// `SALON_OWNER` picks the primary salon from `mySalonsProvider`, falling
  /// back to the My Salons hub when they own none).
  ///
  /// A LITERAL top-level path under the SAME `/salons/` prefix as
  /// [salonPublicProfile] (`/salons/:salonId`, dynamic) — registered BEFORE
  /// that dynamic route, same "declaration order, not specificity" rationale
  /// [mySalons] documents (a second literal under this prefix would
  /// otherwise be swallowed as a `:salonId` value: `/salons/home` would
  /// resolve to the public-profile route with `salonId == 'home'`).
  static const String salonHome = '/salons/home';

  /// Phase 21.8 — the salon-scoped bottom-nav shell
  /// ([SalonHomeResolverScreen] forwards here). `SALON_OWNER`/`SALON_ADMIN`
  /// only — gated by `salonHomeGuard`'s route-level role check plus
  /// `salonManageGuard` (reused VERBATIM from [salonManage]/
  /// [salonManageSettings] — it already binds ownership for both roles) on
  /// the route itself.
  ///
  /// A literal `/shell` suffix on the same `/salons/:salonId` segment
  /// [salonManage]/[salonManageSettings] extend — registered as a STANDALONE
  /// top-level route for the identical "an ancestor's own redirect always
  /// runs" reason those two document, LAST among the four `/salons/:salonId`-
  /// prefixed siblings (declaration order does not matter among them, since
  /// none is a literal that a dynamic sibling could shadow — only [mySalons]
  /// and [salonHome] have that concern, both literals under the shorter
  /// `/salons/` prefix).
  static String salonShell(String salonId) =>
      '${salonPublicProfile(salonId)}/shell';

  /// Phase 21.1 — My Salons Hub, the `SALON_OWNER` landing (see
  /// `role_home.dart`'s `roleHomePath`): every salon the owner holds, listed
  /// as a tappable card, plus the "+ Додати салон" CTA. `SALON_OWNER`-only —
  /// a `SALON_ADMIN` belongs to exactly one salon and lands straight on
  /// [salonManage] instead.
  ///
  /// A LITERAL path under the same `/salons/` prefix as [salonPublicProfile]
  /// (`/salons/:salonId`, dynamic). Registered in `app_router.dart` as a
  /// standalone top-level `GoRoute` (same "cannot nest under `:salonId`"
  /// rationale as [salonManage]) and declared BEFORE the dynamic
  /// `/salons/:salonId` route so the literal wins the match instead of being
  /// shadowed by it — go_router resolves literal-vs-dynamic purely by
  /// declaration order, not specificity.
  static const String mySalons = '/salons/mine';

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

  /// Phase 231 — the master «Архів» page: a paginated, filterable list of
  /// PAST bookings reached from a header button on [masterBookings], from
  /// which a not-yet-closed visit can be closed in place.
  ///
  /// A CHILD of [masterBookings] (`/master/bookings/archive`), NOT a sibling
  /// top-level route — same reasoning as [masterBookingDetail]: it inherits
  /// the `/master/*` prefix role gate in `auth_redirect.dart` (currently
  /// INDEPENDENT_MASTER-only — see that file's own comment on why no other
  /// provider role is carved into `/master/*` yet) for free, and pushes onto
  /// the master's own stack so back returns to the still-scrolled day
  /// timeline. `archive`, not `:something`, because there is exactly one —
  /// no id to parametrise.
  static const String masterBookingsArchive = '$masterBookings/archive';

  /// Phase 247 — the INDEPENDENT_MASTER «Новий запис» wizard: a walk-in
  /// booking the master creates on their own calendar (client → service →
  /// dateTime → confirm → done).
  ///
  /// A CHILD of [masterBookings] (`/master/bookings/new`), registered
  /// BEFORE the `:bookingId` sibling in `app_router.dart` (mirrors
  /// [masterBookingsArchive]'s own reasoning — the literal `new` segment
  /// must never be shadowed by the dynamic one) — inherits the `/master/*`
  /// INDEPENDENT_MASTER role gate for free. Rendered as a fullscreen-dialog
  /// page. Reached with `context.push`, never `Navigator` — CI fails on
  /// `Navigator` in `lib/features/`. The Phase 248 «+» entry point is the
  /// only planned caller so far.
  static const String masterBookingNew = '$masterBookings/new';

  /// Phase 264 — the walk-in chain's second screen: service multi-selection,
  /// reached with a [WalkInGuest] in `extra` (minted by
  /// `WalkInGuestStepScreen`'s «Далі»). A CHILD of [masterBookingNew] (`
  /// /master/bookings/new/services`), registered as a nested `routes:` child
  /// in `app_router.dart` — NOT a second top-level literal — so the
  /// `archive` / `new` / `:bookingId` literal-before-dynamic ordering under
  /// [masterBookings] is not perturbed at all (mirrors how `time` nests
  /// under [bookingSlots] above). Derived from [masterBookingNew] itself so
  /// the two constants can never drift apart.
  static const String masterBookingNewServices = '$masterBookingNew/services';

  /// Phase 250 — the STAFF-side salon booking surfaces (`/salon/bookings/…`),
  /// `SALON_OWNER`/`SALON_ADMIN` only.
  ///
  /// NOT to be confused with [salonBookingServices]/[salonBookingMasters]/
  /// [salonBookingTime]/[salonBookingConfirm]/[salonBookingSuccess] above
  /// (all under `/booking/salon/…`, CLIENT-guarded) — those are a CLIENT
  /// booking AT a salon. This is SALON STAFF creating a walk-in booking ON
  /// BEHALF of the salon, mirroring [masterBookings]'s own shape one level
  /// up (`/master/bookings/…`, INDEPENDENT_MASTER-only) for the salon role
  /// pair instead.
  static const String salonStaffBookings = '/salon/bookings';

  /// Phase 250 — the SALON «Новий запис» 6-step wizard (client → service →
  /// dateTime → masters → confirm → done): a walk-in booking a
  /// `SALON_OWNER`/`SALON_ADMIN` creates on behalf of the salon, choosing
  /// which of the salon's masters performs it.
  ///
  /// A literal child of [salonStaffBookings] — today it is the ONLY route
  /// registered under that prefix (`app_router.dart` registers it as a
  /// STANDALONE top-level `GoRoute`, mirroring [RouteNames.clientReview]'s
  /// own "no shell to nest under" reasoning; see that route's registration
  /// comment). If a future phase adds a dynamic sibling — most likely a
  /// `/salon/bookings/:bookingId` detail route, mirroring
  /// [masterBookingDetail] — it MUST be declared AFTER this literal `new`
  /// segment wherever the two become siblings under one parent `GoRoute`,
  /// exactly like [masterBookingNew]'s own doc explains (go_router resolves
  /// literal-before-dynamic ONLY by declaration order among siblings; see
  /// `test/routing/master_bookings_route_shadowing_test.dart`, mirrored here
  /// by `test/routing/salon_bookings_route_shadowing_test.dart`).
  ///
  /// Inherits the `/salon/*` `SALON_OWNER`/`SALON_ADMIN` role gate added to
  /// `auth_redirect.dart` for this phase — see that file's own comment.
  /// Rendered as a fullscreen dialog. Reached with `context.push`, carrying
  /// the target salon id (a bare `String`) in `extra` — mirrors
  /// [salonBookingServices]'s own "no natural upstream salon id" shape, since
  /// nothing on this route's own path carries it. Never `Navigator` — CI
  /// fails on `Navigator` in `lib/features/`.
  static const String salonStaffBookingNew = '$salonStaffBookings/new';

  /// Track 7.x Wave B — «ВІДГУК ПРО КЛІЄНТА» (leave-client-feedback).
  ///
  /// Same URL shape as [masterBookingDetail]'s `/review` child would be, but
  /// registered in `app_router.dart` as a STANDALONE top-level `GoRoute`
  /// (mirroring the `/masters/:masterId` + `/masters/:masterId/reviews`
  /// sibling pair), NOT nested under it — nesting under a plain content
  /// screen (not a shell) made go_router insert the detail route's own match
  /// into every push, silently mounting a shadow `BookingDetailScreen`
  /// underneath the review screen and breaking pop-back for the archive
  /// entry path. See the route registration's own comment in
  /// `app_router.dart` for the full investigation. A push here therefore
  /// pops back to whatever the caller actually had on the stack: the
  /// [masterBookingDetail] screen when reached from its COMPLETED-provider-
  /// booking entry CTA (`_DetailBody._providerActions`), or the
  /// `/master/bookings/archive` list when reached from there
  /// (`master_archive_screen.dart`).
  ///
  /// GATING — like [bookingReview]'s `canReview`, both entry points gate their
  /// CTA on a server-computed flag: `Booking.providerCanReviewClient`, which
  /// carries a real per-row value on `GET /bookings/{id}` AND on the provider
  /// rows of `GET /bookings/me` (backend `fix/list-provider-can-review-client`,
  /// 2026-08-17). The destination then RE-GATES on its own
  /// `GET /bookings/{id}`, pre-empting a stale list row before the form is ever
  /// built, and a duplicate submit's 409 remains the last backstop — see
  /// `LeaveClientFeedbackScreen`'s file header.
  ///
  /// (The earlier note here — "there is no server-computed canReview-equivalent
  /// flag for the provider side yet, so the CTA is offered on every COMPLETED
  /// provider booking" — was false on both halves by 2026-08-17 and is
  /// deleted rather than softened: it read as an instruction to re-widen the
  /// gate that fixed the already-reviewed-row bug.)
  ///
  /// `extra` on a push here carries the ENTRY POINT (`ClientReviewEntry`) — see
  /// the route's registration comment in `app_router.dart`. It never appears in
  /// the path this method builds.
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
  //
  // Optional `?date=yyyy-MM-dd` query param (added alongside the master
  // bookings screen's "no working hours" empty state): pre-selects that date
  // instead of today (`MasterScheduleScreen.initialDate`, parsed in
  // `app_router.dart` via `parseApiDate`). Built ad hoc at its one call site
  // (`master_bookings_screen.dart`'s `onAddWorkingHours`, mirroring
  // [services]'s `?expandCategory=` precedent below) rather than a dedicated
  // helper here — a second call site should promote it to one.
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
