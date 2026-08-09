// Phase 13.5 — E2E: CLIENT public master-profile journey + the role guard.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/master/presentation/public_master_profile_screen_test.dart)
// proves PublicMasterProfileScreen in isolation with the
// publicMasterProfileProvider family STUBBED. Neither it nor the notifier unit
// test exercises the REAL journey: a CLIENT logging in, navigating to
// `/masters/:masterId` (the search/favourites card push target), the route
// guard ADMITTING the CLIENT, the real publicMasterProfileProvider firing BOTH
// real repositories (masterRepository.getMasterById +
// publicServiceRepository.getMasterServices) against the backend, the identity
// card + services-count rendering from that response, the favourite heart
// POSTing a favorite, and the «Записатись» CTA pushing the booking-new route.
//
// It also pins the CLIENT-ONLY route guard end to end: an INDEPENDENT_MASTER who
// reaches `/masters/:masterId` is REDIRECTED to /master/profile (clientOnlyGuard
// → roleHomePath), and the public-detail endpoint is therefore never touched.
//
// CLIENT 403-DECOUPLING REGRESSION (mirrors client_search_flow): the public
// profile must source the master through the public `GET /masters/{id}` path
// (counted as [getPublicMasterCalls]) and NEVER the master-only `GET /masters/me`
// (counted as [getMasterCalls]) — the latter 403s for a CLIENT and triggers
// Riverpod's retry storm. Both flows assert `fb.getMasterCalls == 0`.
//
// This boots the REAL app via AppHarness (FakeBackend socket, FakeSecureStorage,
// fixed clock, overflow guard) and drives the whole flow against the fake
// backend's seeded `master-aaa` public detail + two-service list.
//
// KEY POLICY: navigation taps are key-based (public-master-favorite-toggle,
// public-master-book-cta). Raw find.text(...) is used only for content
// assertions (the master's name is backend data). See
// integration_test/support/app_harness.dart.
//
// PHASE 14.1 EXTENSION (mobile-qa, 2026-07-02): Flow A no longer stops at the
// «Записатись» push — it continues through the REAL booking flow that phase
// shipped: ServiceSelectorSheet (select a service from the NAILS category) →
// SlotDateScreen (pick "today") → SlotTimeScreen (pick the first available
// chip) → the (still-stubbed, Phase 14.2) `/booking/confirm` placeholder.
// This is the ONLY E2E coverage of the multi-screen booking journey wired
// through the real router + real repositories against `FakeBackend` (the
// widget-level `service_selector_sheet_test.dart` / `slot_picker_test.dart`
// each cover one screen in isolation with hand-rolled routers). The new
// `GET /api/v1/masters/master-aaa/slots` fixture lives in
// `support/fake_backend.dart` (`_availableSlotsEnvelope`,
// `getMasterSlotsCalls`).
//
// PHASE 14.14 EXTENSION: `SlotDateScreen` now gates every day cell on a real
// `GET /masters/{id}/working-days` fetch (`workingDaysProvider`) instead of
// treating every non-past day as tappable — this flow asserts that fetch
// actually landed (`fb.getWorkingDaysCalls`) before "today" is tapped. The
// fixture (`_workingDaysEnvelope`, `getWorkingDaysCalls`) lives alongside
// `_availableSlotsEnvelope` in `support/fake_backend.dart`.
//
// LOCAL-EMULATOR CAVEAT: the shared client integration harness drives the real
// VM-service websocket and may not run green from the VirtualBox VM without the
// host-only adapter UP (see MEMORY: "Integration tests need host-only adapter to
// drive"). This flow is authored + `flutter analyze`-clean; confirm the green run
// on CI / a directly-driven emulator.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_reviews_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // Shared preamble for Flow A / Flow C: log in as CLIENT, push the public
  // profile, open the NAILS category, select the first service, and land on
  // SlotDateScreen («Оберіть дату») via the real router + real repositories
  // against [fb]. Factored out so Flow C (Phase 14.14 QA gap-fix) doesn't
  // re-duplicate Flow A's ~40-line navigation preamble just to reach the same
  // screen under test.
  Future<void> bootToSlotDateScreen(
    WidgetTester tester,
    FakeBackend fb,
    GoRouter router,
  ) async {
    await AppHarness.loginAs(tester, fb, UserRole.client);
    // fixed-wait-ok: settles the real async login/route-transition step; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
    // fixed-wait-ok: settles the real async route-push + provider-load step; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final Finder cta = find.byKey(const Key('public-master-book-cta'));
    await tester.tap(cta);
    // fixed-wait-ok: settles the real async route-push step after the tap; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final Finder categoryHeader = find.byKey(
      const Key('booking_category_NAILS'),
    );
    await tester.tap(categoryHeader);
    await tester.pumpAndSettle();

    final Finder serviceTile = find.byKey(
      const Key('booking_service_tile_pub-assign-1'),
    );
    await tester.tap(serviceTile);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await tester.pumpAndSettle();

    AppHarness.expectLocation(router, RouteNames.bookingSlots);
    expect(find.byType(SlotDateScreen), findsOneWidget);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Flow A — CLIENT: profile renders → favourite toggles → «Записатись» pushes.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT opens a master public profile → it renders the name/role/services, '
    'the favourite heart POSTs a favorite, and «Записатись» drives the full '
    'booking flow (service select → date → time → the /booking/confirm stub)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Log in as CLIENT → land on the client shell at /home ──────────────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: settles the real async login/route-transition step; duration is pumpAndSettle's poll interval, not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── Navigate to /masters/master-aaa (the search/favourites card target) ─
      // MasterResultCard now wires onTap → context.push(masterPublicProfile)
      // (the TODO(13.5) is resolved). We still drive the SAME destination via
      // router.push directly here rather than tapping a rendered card: reaching a
      // real card would require driving the discovery filters + paged search
      // results off the fake backend first, which is non-deterministic and
      // orthogonal to what this flow pins. The push exercises the identical
      // route + clientOnlyGuard + publicMasterProfile provider stack the card
      // uses, so the journey under test is unchanged.
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      // fixed-wait-ok: settles the real async route-push + provider-load step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, '/masters/master-aaa');
      expect(
        find.byType(PublicMasterProfileScreen),
        findsOneWidget,
        reason: 'the CLIENT guard must ADMIT a CLIENT to the public profile',
      );

      // ── The real provider fired BOTH public reads (NOT /masters/me) ───────
      expect(
        fb.getPublicMasterCalls,
        greaterThanOrEqualTo(1),
        reason: 'the profile must resolve via the public GET /masters/{id}',
      );
      expect(
        fb.getPublicMasterServicesCalls,
        greaterThanOrEqualTo(1),
        reason: 'the services count must come from GET /masters/{id}/services',
      );
      expect(fb.lastGetPublicMasterId, 'master-aaa');

      // ── Identity card + role + services-count rendered from the response ──
      expect(
        find.byKey(const Key('public-master-profile-name')),
        findsOneWidget,
      );
      // i18n-finder-ok: master's display name is fixture data, not UI copy
      expect(find.text('Софія Бондар'), findsOneWidget);
      final Text servicesValue = tester.widget<Text>(
        find.byKey(const Key('public-master-profile-services-value')),
      );
      // PRECONDITION for the assertion below. The stat tile no longer prints
      // the raw length unconditionally — a ZERO count renders the em-dash
      // empty-state instead (ServicesStatTile). So `'$publicMasterServicesCount'`
      // is only the right expectation while the fixture seeds a NON-EMPTY
      // catalogue. If someone later empties `_publicMasterServices`, this line
      // fails loudly here rather than letting the assertion below mis-report a
      // correct '—' render as a broken '0'.
      expect(
        FakeBackend.publicMasterServicesCount,
        greaterThan(0),
        reason:
            'this flow asserts the numeric count branch of the services stat '
            'tile; a zero-service fixture would render "—" instead',
      );
      expect(
        servicesValue.data,
        '${FakeBackend.publicMasterServicesCount}',
        reason: 'the services-count stat must reflect the seeded list length',
      );

      // ── Service-categories section — read-only summary card grouped from
      // the SAME real GET /masters/{id}/services response the stat tile above
      // asserted (fb.getPublicMasterServicesCalls). FakeBackend seeds both
      // `_publicMasterServices` entries under category NAILS, so exactly one
      // card renders with a count matching the seeded list length. This is
      // the ONLY E2E coverage of the section rendering from a REAL backend
      // response (not a stubbed provider) — the widget tier
      // (public_master_profile_screen_test.dart) already covers the grouping
      // logic + the interactive:false security guard exhaustively with
      // multi-category / uncategorized fixtures, which would be pure
      // duplication to re-derive here against the single-category fake-
      // backend fixture. ──────────────────────────────────────────────────
      final Finder nailsCard = find.byKey(
        const Key('public-master-profile-category-NAILS'),
      );
      expect(
        nailsCard,
        findsOneWidget,
        reason:
            'the service-categories section must render from the real '
            'GET /masters/{id}/services response',
      );
      expect(
        find.descendant(
          of: nailsCard,
          matching: find.text('${FakeBackend.publicMasterServicesCount}'),
        ),
        findsOneWidget,
        reason:
            'the NAILS card count badge must reflect the real seeded '
            'service-list length',
      );
      // Read-only for a CLIENT — no owner-only disclosure chevron.
      expect(
        find.descendant(
          of: nailsCard,
          matching: find.byIcon(Icons.arrow_forward_ios_rounded),
        ),
        findsNothing,
        reason:
            'a CLIENT viewing another master\'s profile must never see the '
            'owner-only category-card chevron',
      );

      // This is the read-only client view — no master edit/menu button.
      expect(find.byKey(const Key('btn-menu-master')), findsNothing);

      // ── Tap the favourite heart → optimistic flip → POST /favorites ───────
      expect(fb.addFavoriteCalls, 0);
      await tester.tap(find.byKey(const Key('public-master-favorite-toggle')));
      await tester.pumpAndSettle();

      expect(
        fb.addFavoriteCalls,
        1,
        reason: 'tapping the empty heart must POST exactly one favorite',
      );
      expect(fb.lastAddFavoriteBody?['targetType'], 'MASTER');
      expect(fb.lastAddFavoriteBody?['targetId'], 'master-aaa');

      // ── Tap «Записатись» → push the booking-new route ─────────────────────
      final Finder cta = find.byKey(const Key('public-master-book-cta'));
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      // fixed-wait-ok: settles the real async route-push step after the tap; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, RouteNames.bookingNew);

      // ── 403-decoupling regression — never touched GET /masters/me ─────────
      expect(
        fb.getMasterCalls,
        0,
        reason:
            'the CLIENT public-profile journey must not hit GET /masters/me '
            '(403 decoupling — the public path is GET /masters/{id})',
      );

      // ── Phase 14.1 Step 1: ServiceSelectorSheet renders master-aaa's real
      // (public) catalogue — the SAME two NAILS services the identity-card
      // services-count stat already asserted above. Expand the category and
      // select the first service. ────────────────────────────────────────
      expect(find.byType(ServiceSelectorSheet), findsOneWidget);

      final Finder categoryHeader = find.byKey(
        const Key('booking_category_NAILS'),
      );
      expect(categoryHeader, findsOneWidget);
      await tester.tap(categoryHeader);
      await tester.pumpAndSettle();

      final Finder serviceTile = find.byKey(
        const Key('booking_service_tile_pub-assign-1'),
      );
      expect(serviceTile, findsOneWidget);
      await tester.tap(serviceTile);
      await tester.pumpAndSettle();

      // ── «Далі» pushes /booking/slots (SlotDateScreen — «Оберіть дату») ───
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(find.byType(SlotDateScreen), findsOneWidget);

      // ── Phase 14.14: the calendar day-availability gate fires its real
      // GET /masters/{id}/working-days request BEFORE any day is tappable —
      // FakeBackend's `_workingDaysEnvelope` marks a wide window around
      // "now" as `working: true`, so "today" stays admissible regardless of
      // the real-world date the suite runs on. ─────────────────────────────
      await tester.pumpAndSettle();
      expect(
        fb.getWorkingDaysCalls,
        greaterThanOrEqualTo(1),
        reason:
            'SlotDateScreen must resolve the calendar gate from the real '
            'GET /masters/{id}/working-days endpoint before any day is '
            'tappable, not a stubbed always-available heuristic',
      );

      // ── Pick "today" — admissible per the real working-days response
      // fetched above. This fires the real GET /masters/master-aaa/slots
      // request against FakeBackend. ────────────────────────────────────────
      //
      // Kyiv "today" AS THE APP UNDER TEST COMPUTES IT, derived from the
      // harness's INJECTED clock (`kFixedNow`, 2026-06-14 12:00 UTC), never
      // the host device clock. `SlotDateScreen._today` reads `clockProvider`,
      // which `AppHarness.boot` overrides to `kFixedNow`, so the visible month
      // + "today" cell are always June 2026 no matter what day the suite runs
      // on. The bare `DateTime.now()` this used to read instead passed only by
      // ACCIDENT, whenever the real run date's day-of-month happened to land
      // on/after the 14th — any run on the 1st–13th tapped an ALREADY-PAST
      // June cell, which `MonthCalendar` renders with `onTap: null` and no
      // `GestureDetector` at all, so the tap is a silent no-op: no
      // `GET /masters/{id}/slots` fires and «Далі» never navigates, killing
      // the flow with "SlotTimeScreen: found 0 widgets". Mirrors
      // `client_reschedule_flow_test.dart` and `master_bookings_flow_test
      // .dart`'s `_kyivToday` (same fix, same reasoning). DO NOT regress this
      // back to a host-clock read.
      final DateTime today = kyivToday(() => kFixedNow);
      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);
      // `tapCalendarDay` scrolls the cell into view first — a blind tap on a
      // below-the-fold row lands on the summary bar instead (see the
      // extension's doc comment in test/helpers/pump_app.dart).
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();

      expect(
        fb.getMasterSlotsCalls,
        greaterThanOrEqualTo(1),
        reason:
            'picking a day must fetch that day\'s slots from the real '
            'GET /masters/{id}/slots endpoint, not a stubbed provider',
      );

      // ── «Далі» pushes /booking/slots/time (SlotTimeScreen — «Оберіть час»)
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      AppHarness.expectLocation(router, RouteNames.bookingSlotsTime);
      expect(find.byType(SlotTimeScreen), findsOneWidget);

      // ── Pick the first available chip → «Підтвердити» enables ────────────
      final Finder availableChip = find.byWidgetPredicate(
        (Widget w) => w is SlotChip && w.available,
      );
      expect(availableChip, findsWidgets);
      await tester.tap(availableChip.first);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      // ── Lands on the REAL /booking/confirm screen ─────────────────────────
      //
      // This used to assert `booking-confirm-placeholder`, the Phase 14.1 stub
      // (`BookingConfirmPlaceholderScreen`). Phase 14.2 replaced that route's
      // builder with the real [BookingConfirmScreen] — the placeholder widget
      // still exists in `lib/features/shell/presentation/branch_placeholders
      // .dart` but is no longer routed from anywhere, so the key can never
      // mount. The stale assertion never surfaced because the blind calendar
      // tap above (finding #2) killed this flow long before line 356.
      AppHarness.expectLocation(router, RouteNames.bookingConfirm);
      expect(
        find.byType(BookingConfirmScreen),
        findsOneWidget,
        reason:
            'the time screen\'s «Підтвердити» CTA must hand off to '
            '/booking/confirm with a BookingConfirmArgs extra',
      );
      expect(
        find.byKey(const Key('booking-confirm-visit-card')),
        findsOneWidget,
        reason: 'the confirm screen recaps the visit it was handed',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Flow B — INDEPENDENT_MASTER hitting the CLIENT-only profile route is
  // REDIRECTED to its own home (/master/profile); the public profile never
  // mounts and the public-detail endpoint is never hit.
  //
  // This pins the production [clientOnlyGuard] redirect end to end — a refactor
  // that drops the guard would silently let a master view the client-facing
  // profile, and this flow would catch it (the public route would mount).
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'INDEPENDENT_MASTER reaching /masters/:id is redirected to /master/profile '
    '(CLIENT-only route guard)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      // fixed-wait-ok: settles the real async login/route-transition step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // Attempt to reach the CLIENT-facing public profile.
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      // fixed-wait-ok: settles the real async guard-redirect route-push step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // clientOnlyGuard → roleHomePath(independentMaster) → /master/profile.
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      expect(
        find.byType(PublicMasterProfileScreen),
        findsNothing,
        reason: 'a non-CLIENT must never mount the public master profile',
      );
      expect(
        fb.getPublicMasterCalls,
        0,
        reason: 'the redirect must fire BEFORE the public detail is fetched',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Flow C — Phase 14.14 QA gap-fix: the calendar gate's NEGATIVE path,
  // proven against the real GET /masters/{id}/working-days endpoint, not a
  // widget-level fake. Flow A above only ever exercises the fixture with
  // EVERY day marked `working: true`, so it proves the fetch fires but never
  // proves a day the endpoint marks non-working actually blocks the flow
  // end-to-end (that contract was previously pinned only at the widget tier,
  // in slot_picker_test.dart, against a hand-rolled fake repository).
  //
  // "Today" is deliberately the forced-non-working day (rather than a
  // relative "tomorrow"/"last day of month" pick) so the assertion is
  // 100% real-world-date-safe — no month-boundary edge case, and it directly
  // mirrors Flow A's "tap today" happy path with the ONE variable (the
  // endpoint's `working` verdict for that exact date) flipped.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'SlotDateScreen: a day the real GET /masters/{id}/working-days endpoint '
    'marks working:false renders untappable and never fetches slots or '
    'advances the flow (E2E, not just fixture wiring)',
    (tester) async {
      // Kyiv "today" AS THE APP UNDER TEST COMPUTES IT — see the identical
      // note in Flow A. Here it is NOT cosmetic: `forceNonWorkingDate` must
      // name a date the calendar ACTUALLY RENDERS and that is NOT already
      // past, or the "no GestureDetector" assertion below passes for the WRONG
      // REASON. Under the old `DateTime.now()` read the forced date was the
      // real-world today (e.g. 2026-08-04) — a date the visible month (June
      // 2026, pinned by `kFixedNow`) never renders — while the cell actually
      // probed was June-of-that-day-number, untappable merely because it was
      // PAST. The assertion was therefore VACUOUS and proved nothing about the
      // Phase 14.14 working-days gate. Reading the injected clock makes the
      // forced date 2026-06-14 — rendered, not past, and the very cell the
      // assertion probes — restoring the intended negative-path coverage.
      final DateTime todayDateOnly = kyivToday(() => kFixedNow);
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..forceNonWorkingDate = todayDateOnly;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await bootToSlotDateScreen(tester, fb, router);

      // The real endpoint really fired and really reported today as
      // non-working (not a stubbed always-available heuristic).
      expect(fb.getWorkingDaysCalls, greaterThanOrEqualTo(1));

      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${todayDateOnly.day}'),
      );
      expect(todayCell, findsOneWidget);
      expect(
        find.descendant(of: todayCell, matching: find.byType(GestureDetector)),
        findsNothing,
        reason:
            'a day the real endpoint marked working:false must render '
            'without a tap handler',
      );

      await tester.tap(todayCell, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        fb.getMasterSlotsCalls,
        0,
        reason:
            'a forced tap on a non-working day must never fetch that '
            'day\'s slots from the real GET /masters/{id}/slots endpoint',
      );

      // «Далі» stays disabled — no date was ever accepted as selected.
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(
        find.byType(SlotTimeScreen),
        findsNothing,
        reason: 'the flow must never advance past a rejected day tap',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Flow D — Phase 14.20 REGRESSION (E2E): the calendar-vs-slots availability
  // bug. Before the fix, `SlotDateScreen` requested working-days in
  // SCHEDULE-SHAPE mode (no serviceId), so a day the master had intervals on
  // rendered SELECTABLE even when the chosen service's duration left it with
  // zero bookable slots — tapping it dead-ended on «Немає вільного часу». The
  // fix threads `services.first.id` into the working-days query, putting it in
  // the same AVAILABILITY-AWARE mode `/slots` uses.
  //
  // This flow drives the WHOLE journey against the real router + repositories
  // and asks the fake backend to mark "today" non-working ONLY WHEN the
  // request carries a serviceId (`forceNonWorkingDateWhenServiceScoped`). So it
  // discriminates the two code paths end-to-end: pre-fix code sends no
  // serviceId → the endpoint answers schedule-shape → today is working:true →
  // the client taps through to the dead-end; the fixed code sends the
  // serviceId → today is working:false → the cell is inert and the dead-end is
  // unreachable. "Today" is the forced day so the assertion is
  // real-world-date-safe (mirrors Flow C).
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'SlotDateScreen: a day with no slot for the CHOSEN SERVICE is disabled '
    'because the calendar threads the serviceId into GET /working-days — the '
    'client can never tap through to the «Немає вільного часу» dead-end '
    '(Phase 14.20 regression, E2E)',
    (tester) async {
      // Kyiv "today" AS THE APP UNDER TEST COMPUTES IT — same reasoning as
      // Flow C above, and vacuous for the same reason before this fix: the
      // forced date has to be one the calendar RENDERS and that is NOT past,
      // or the "no GestureDetector" / "no slots fetched" assertions below hold
      // trivially (past cell) rather than because the service-scoped
      // working-days answer disabled the day. Only the
      // `lastMasterAaaWorkingDaysServiceId` assertion was ever load-bearing
      // here; the rest of the flow now is too.
      final DateTime todayDateOnly = kyivToday(() => kFixedNow);
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..forceNonWorkingDateWhenServiceScoped = todayDateOnly;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await bootToSlotDateScreen(tester, fb, router);

      // The calendar issued a SERVICE-SCOPED working-days request: the chosen
      // service's id (the ServiceSelectorSheet's `pub-assign-1`) rode along, so
      // the endpoint answered in availability-aware mode. A `null` here would
      // mean the calendar silently fell back to schedule-shape — the pre-fix
      // bug this whole flow guards.
      expect(fb.getWorkingDaysCalls, greaterThanOrEqualTo(1));
      expect(
        fb.lastMasterAaaWorkingDaysServiceId,
        'pub-assign-1',
        reason:
            'the booking calendar must thread services.first.id into '
            'GET /working-days — without it the day resolves schedule-shape-'
            'working and the dead-end bug returns',
      );

      // Today is therefore disabled (no tap handler).
      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${todayDateOnly.day}'),
      );
      expect(todayCell, findsOneWidget);
      expect(
        find.descendant(of: todayCell, matching: find.byType(GestureDetector)),
        findsNothing,
        reason:
            'a day unbookable for the chosen service must render without a tap '
            'handler once the calendar is service-scoped',
      );

      // Forcing a tap never fetches slots and never advances the flow, so the
      // «Немає вільного часу» time screen is unreachable for this day.
      await tester.tap(todayCell, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        fb.getMasterSlotsCalls,
        0,
        reason:
            'a forced tap on a service-unbookable day must never fetch slots',
      );
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(
        find.byType(SlotTimeScreen),
        findsNothing,
        reason:
            'the client must never reach the time screen (the «Немає вільного '
            'часу» dead-end) for a day unbookable with the chosen service',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Flow E — Phase 4.x REGRESSION (E2E): the public-profile «Відгуки» stat
  // tile used to render with NO GestureDetector at all — tapping it was a
  // silent no-op (the user-reported bug). The fix wraps it in a
  // GestureDetector whose onTap calls `context.push(RouteNames.
  // masterPublicReviews(masterId))`, using the trusted route param
  // (`widget.masterId`) — never `master.id`, a value round-tripped through
  // the profile response. This flow drives the REAL tap on the REAL rendered
  // tile (never `router.go`/`router.push` standing in for the tap) and
  // proves it lands on `PublicMasterReviewsScreen`, which renders THAT
  // master's real reviews via the PUBLIC
  // `GET /masters/master-aaa/reviews[/summary]` endpoints — never the
  // `masterRowId`-keyed AUTHENTICATED-master self routes
  // ([FakeBackend.getMasterReviewSummaryCalls] / [getMasterReviewsCalls]),
  // which a CLIENT session has no business ever touching.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('CLIENT taps the «Відгуки» stat tile on a master public profile → '
      'PublicMasterReviewsScreen opens and renders THAT master\'s real reviews '
      '(previously a silent no-op — the reported bug)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    // fixed-wait-ok: settles the real async login/route-transition step; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
    // fixed-wait-ok: settles the real async route-push + provider-load step; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    AppHarness.expectLocation(router, '/masters/master-aaa');

    // ── Tap the REAL rendered reviews stat tile (the tap the bug report was
    // about) — NOT a `router.push`/`router.go` stand-in for it. ────────────
    final Finder reviewsTile = find.byKey(
      const Key('public-master-profile-reviews-tile'),
    );
    expect(reviewsTile, findsOneWidget);
    await tester.ensureVisible(reviewsTile);
    await tester.tap(reviewsTile);
    // fixed-wait-ok: settles the real async route-push + review-provider loads; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The bug was a SILENT no-op — the first and most important assertion
    // is simply that navigation happened at all.
    AppHarness.expectLocation(router, '/masters/master-aaa/reviews');
    expect(find.byType(PublicMasterReviewsScreen), findsOneWidget);

    // ── The real PUBLIC reviews endpoints fired for master-aaa … ──────────
    expect(
      fb.getPublicMasterReviewSummaryCalls,
      greaterThanOrEqualTo(1),
      reason:
          'the summary must load from the PUBLIC '
          'GET /masters/master-aaa/reviews/summary route',
    );
    expect(
      fb.getPublicMasterReviewsCalls,
      greaterThanOrEqualTo(1),
      reason:
          'the list must load from the PUBLIC '
          'GET /masters/master-aaa/reviews route',
    );
    // … and NEVER the `masterRowId`-keyed AUTHENTICATED-master self routes —
    // a CLIENT viewing another master's public reviews must never resolve
    // "its own" reviews (there is no session master row to confuse it with
    // here, but this pins the two surfaces staying on separate routes).
    expect(
      fb.getMasterReviewSummaryCalls,
      0,
      reason:
          'must never hit the AUTHENTICATED master\'s own reviews-summary '
          'route from the public CLIENT journey',
    );
    expect(
      fb.getMasterReviewsCalls,
      0,
      reason:
          'must never hit the AUTHENTICATED master\'s own reviews-list '
          'route from the public CLIENT journey',
    );

    // ── master-aaa's seeded public reviews render (distinct ids from the
    // `mr-*` self-fixture, so a wrong-route mixup would show as findsNothing
    // here rather than silently passing). ─────────────────────────────────
    expect(find.byKey(const Key('master-review-pub-r1')), findsOneWidget);
    expect(find.byKey(const Key('master-review-pub-r2')), findsOneWidget);
    final Text avg = tester.widget<Text>(
      find.byKey(const Key('master-review-summary-average')),
    );
    expect(
      avg.data,
      FakeBackend.kPublicMasterAvgRatingBeforeReview.toStringAsFixed(1),
      reason: 'the summary average must bind from the real response data',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ──────────────────────────────────────────────────────────────────────────
  // Flow G — the «Рейтинг» stat tile was made tappable to mirror the
  // «Відгуки» tile above: it pushes the SAME `RouteNames.masterPublicReviews
  // (masterId)` destination via the SAME production `context.push(...)` call.
  //
  // At the source level both tiles currently share the textually identical
  // `onTap: () => context.push(RouteNames.masterPublicReviews(masterId))`
  // closure, so this flow deliberately does NOT re-derive Flow E's full
  // content assertions (summary average, both seeded review cards, the
  // public-vs-self endpoint decoupling) — that would be pure duplication of
  // the same production code path already proven end-to-end above. What THIS
  // flow adds that Flow E cannot: it drives a REAL tap on the rating tile's
  // OWN, DISTINCT `GestureDetector` (`public-master-profile-rating-tile`), so
  // if a future edit ever gives the rating tile its own (buggy) onTap — e.g.
  // reverting to no handler, or wiring `master.id` instead of the trusted
  // route param — this flow catches it independently of the reviews tile,
  // against the real router + real fake-backend endpoints, not a stub.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('CLIENT taps the «Рейтинг» stat tile on a master public profile → '
      'PublicMasterReviewsScreen opens via the real context.push and the real '
      'public reviews endpoints fire for that master', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    // fixed-wait-ok: settles the real async login/route-transition step; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
    // fixed-wait-ok: settles the real async route-push + provider-load step; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    AppHarness.expectLocation(router, '/masters/master-aaa');

    // ── Tap the REAL rendered rating stat tile — its OWN GestureDetector,
    // distinct from the reviews tile Flow E already exercised. ───────────
    final Finder ratingTile = find.byKey(
      const Key('public-master-profile-rating-tile'),
    );
    expect(ratingTile, findsOneWidget);
    await tester.ensureVisible(ratingTile);
    await tester.tap(ratingTile);
    // fixed-wait-ok: settles the real async route-push + review-provider loads; not a total-wait guess.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    AppHarness.expectLocation(router, '/masters/master-aaa/reviews');
    expect(find.byType(PublicMasterReviewsScreen), findsOneWidget);

    // The real PUBLIC endpoints fired for master-aaa — never the
    // AUTHENTICATED master's own self-scoped routes.
    expect(
      fb.getPublicMasterReviewSummaryCalls,
      greaterThanOrEqualTo(1),
      reason:
          'the summary must load from the PUBLIC '
          'GET /masters/master-aaa/reviews/summary route',
    );
    expect(
      fb.getPublicMasterReviewsCalls,
      greaterThanOrEqualTo(1),
      reason:
          'the list must load from the PUBLIC '
          'GET /masters/master-aaa/reviews route',
    );
    expect(fb.getMasterReviewSummaryCalls, 0);
    expect(fb.getMasterReviewsCalls, 0);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
