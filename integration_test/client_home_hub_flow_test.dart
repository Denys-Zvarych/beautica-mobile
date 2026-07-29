// Phase 13.7 (revised) — E2E: CLIENT Home Hub flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/home/presentation/home_hub_screen_test.dart +
// home_hub_supplemental_test.dart) proves each card widget in isolation and the
// ScreenProtector lifecycle. Neither exercises the REAL journey: a CLIENT
// logging in through the real login form against the fake backend, landing on
// /home, and seeing the Home Hub rendered with provider state from the real
// auth session.
//
// This flow boots the REAL app via AppHarness (FakeBackend socket,
// FakeSecureStorage, fixed clock, overflow guard) and drives:
//
//   1. CLIENT login → lands on /home (HomeHubScreen mounted as branch 0).
//   2. Home Hub renders: beautica wordmark, bell button, burger button.
//   3. The BEAUTY PASSPORT brand literal is present in the stat-pills row.
//   4. The BEAUTY TIMELINE brand literal is present in the timeline section.
//   5. The 3 quick-links tiles are rendered (search / favorites / bookings).
//   6. Next-appointment, favorites, and timeline show their empty states
//      (backend 19.x not yet wired — they are placeholder providers).
//   7. Role gate (reuses client_shell_flow_test.dart contracts — the gate
//      itself is already proven there; here we confirm /home landing only):
//      an INDEPENDENT_MASTER who navigates to /home is bounced to
//      /master/profile; /rating is also gated.
//   8. The "Мій рейтинг" stat pill is rendered in the stat-pills row.
//
// BEAUTY PASSPORT / BEAUTY TIMELINE LITERALS
// ------------------------------------------
// These are intentionally untranslated English brand constants (per the locked
// product decision). Tests assert find.textContaining('BEAUTY PASSPORT') and
// find.textContaining('BEAUTY TIMELINE') — raw-string assertions are correct
// here because there is no l10n key for these literals.
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders. Raw Ukrainian
// text may appear in CONTENT ASSERTIONS only.
//
// FAKE-BACKEND GAPS
// -----------------
// GET /clients/me/passport, GET /bookings/me, GET /favorites/masters,
// GET /clients/me/timeline, GET /clients/me/rating — not yet wired in FakeBackend
// (backend 19.x). Their providers return empty/null placeholders so the Hub shows
// empty states; the integration test asserts the empty-state keys to confirm this.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // ── Test 1 — CLIENT login lands on /home (HomeHubScreen) ─────────────────

  testWidgets(
    'CLIENT login lands on /home and HomeHubScreen mounts with all key widgets',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start → /login.
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'cold start (no token) must show /login',
      );

      await AppHarness.loginAs(tester, fb, UserRole.client);
      // Allow the stagger animation to play so all hub sections become visible.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Must be at /home.
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // HomeHubScreen must be mounted.
      expect(
        find.byType(HomeHubScreen),
        findsOneWidget,
        reason:
            'HomeHubScreen must mount as the branch-0 body of the client shell',
      );

      // Top bar: wordmark.
      expect(
        find.text('beautica'),
        findsOneWidget,
        reason: 'top bar must render the beautica wordmark',
      );

      // Top bar buttons.
      expect(
        find.byKey(const Key('home_hub_bell_button')),
        findsOneWidget,
        reason: 'bell button must be present in the top bar',
      );
      expect(
        find.byKey(const Key('home_hub_menu_button')),
        findsOneWidget,
        reason: 'burger menu button must be present in the top bar',
      );

      expect(fb.loginCalls, equals(1));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 2 — BEAUTY PASSPORT + BEAUTY TIMELINE brand literals ────────────

  testWidgets(
    'BEAUTY PASSPORT and BEAUTY TIMELINE brand literals render in the hub',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // These are intentional English brand constants — the only raw-string
      // assertions in this file.
      expect(
        find.textContaining('BEAUTY PASSPORT'),
        findsOneWidget,
        reason:
            'PassportPreviewCard must render the "BEAUTY PASSPORT" brand literal '
            '(intentionally untranslated per product decision)',
      );
      expect(
        find.textContaining('BEAUTY TIMELINE'),
        findsOneWidget,
        reason:
            'BeautyTimelineSection must render the "BEAUTY TIMELINE" brand literal '
            '(intentionally untranslated per product decision)',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 3 — Quick-links tiles rendered ──────────────────────────────────

  testWidgets(
    'all 3 quick-link tiles render in the home hub (reviews removed from quick-links)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      for (final String key in <String>[
        'quick_link_search',
        'quick_link_favorites',
        'quick_link_bookings',
      ]) {
        expect(
          find.byKey(Key(key)),
          findsOneWidget,
          reason: '$key quick-link tile must be present in the home hub',
        );
      }

      // The reviews quick-link was removed; rating is reached via the stat pill.
      expect(
        find.byKey(const Key('quick_link_reviews')),
        findsNothing,
        reason:
            'quick_link_reviews must be absent — rating navigation is via '
            'the MyRatingStatCard stat pill',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 4 — empty states for placeholder sections ────────────────────────

  testWidgets('next-appointment, favorites, and timeline show empty states '
      '(backend 19.x not yet wired)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // NextAppointmentCard empty state key.
    expect(
      find.byKey(const Key('next_appointment_empty')),
      findsOneWidget,
      reason:
          'next-appointment section must show its empty state because the '
          'bookings endpoint (backend 19.3) is not yet wired',
    );

    // FavoriteMastersCard empty state key.
    expect(
      find.byKey(const Key('favorite_masters_empty')),
      findsOneWidget,
      reason:
          'favorites section must show its empty state because the '
          'favorites endpoint (backend 19.1) is not yet wired',
    );

    // BeautyTimelineSection empty state key.
    expect(
      find.byKey(const Key('timeline_empty')),
      findsOneWidget,
      reason:
          'timeline section must show its empty state because the '
          'timeline endpoint (backend 19.5) is not yet wired',
    );
  }, timeout: const Timeout(Duration(seconds: 45)));

  // ── Test 5 — "Мій рейтинг" stat pill is rendered in the hub ────────────

  testWidgets(
    '"Мій рейтинг" stat pill renders in the stat-pills row',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The stat pill must render "Мій рейтинг" (l10n.homeHubMyRating).
      expect(
        find.textContaining('Мій рейтинг'),
        findsOneWidget,
        reason:
            'MyRatingStatCard must render "Мій рейтинг" in the stat-pills row',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 6 — role gate: INDEPENDENT_MASTER bounced off /home ─────────────

  testWidgets(
    'role gate: an INDEPENDENT_MASTER navigating to /home is bounced to '
    '/master/profile; /rating is also bounced',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Master lands on /master/profile after login.
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // Attempt to navigate to /home — must be bounced back.
      router.go(RouteNames.clientHome);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      expect(
        find.byType(HomeHubScreen),
        findsNothing,
        reason: 'HomeHubScreen must never mount for INDEPENDENT_MASTER',
      );

      // Attempt /rating — also gated.
      router.go(RouteNames.myRating);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      expect(
        find.byKey(const Key('my_rating_back_button')),
        findsNothing,
        reason: 'MyRatingScreen must never mount for INDEPENDENT_MASTER',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 7 — REGRESSION: saved city resolves from the taxonomy on /home ──
  //
  // BUG (fixed): clientProfile mapped `city: user.cityName ?? ''` (the
  // denormalized string). When the backend returned an empty cityName but a
  // populated cityId/oblastId FK — the authoritative locality — the Home Hub
  // profile card fell to its "add location" placeholder while Settings (which
  // resolves the name from the location taxonomy by id) correctly showed the
  // city. The fix routes the name through `_resolveCityName` → cityListProvider.
  //
  // This flow drives the REAL wiring the provider unit test fakes:
  //   HomeHubScreen → real clientProfile → real cityListProvider → real
  //   LocationRepository → GET /users/me (cityId set, cityName empty) +
  //   GET /locations/oblasts/oblast-kyiv/cities (resolves "Київ").
  //
  // The FakeBackend client body carries cityId/cityName from its mutable client
  // state; we seed cityId='city-kyiv' with a NULL cityName — exactly the bug
  // condition (FK set, denormalized name absent). The seeded cities route
  // returns the "Київ" city with id 'city-kyiv', so the taxonomy match resolves.
  // Asserting the literal "Київ" renders on the card guards the regression at
  // the screen tier; if clientProfile ever reverts to `user.cityName ?? ''` the
  // card would show the placeholder and this test fails.

  testWidgets(
    'REGRESSION: CLIENT with cityId set but empty cityName sees the city '
    'resolved from the taxonomy on the Home Hub profile card',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // Bug condition: authoritative FK present, denormalized name absent.
        ..clientCityId = 'city-kyiv'
        ..clientCityName = null;

      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      // Allow the stagger animation + the cityListProvider taxonomy fetch to
      // settle so the resolved name is painted on the card.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The profile card's location row must show the resolved city name, NOT
      // the l10n "add location" placeholder. The card renders profile.city as
      // literal text — a raw-string assertion is correct here because the value
      // is backend data (a city name), not a localised key.
      expect(
        find.text('Київ'),
        findsOneWidget,
        reason:
            'Home Hub profile card must resolve the saved city ("Київ") from '
            'the location taxonomy via cityId when User.cityName is empty — '
            'regression guard for clientProfile city resolution',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 8 — REGRESSION (Rule 3b): in-page Passport tile syncs the navbar ──
  //
  // The widget-tier guard (test/features/shell/home_inpage_branch_hop_test.dart)
  // ALREADY proves the page↔navbar semantics-selection sync against a
  // purpose-built shell router (same ensureSemantics()/isSelected pattern) —
  // safely, because widget tests run against a host-only fake semantics
  // binding. This flow instead confirms the ROUTE side of the same sync
  // survives the full production stack: real appRouter, real auth session,
  // real ClientShell + ClientBottomNav. It does NOT re-assert the nav-tile
  // semantics-selected state here: `tester.ensureSemantics()` activates the
  // REAL Android accessibility tree on a device/emulator (not a host-only
  // fake), and doing so was found to corrupt IntegrationTestWidgetsFlutter-
  // Binding's one-time final teardown — every assertion in this flow (and
  // every other flow run alongside it) passed, but the whole test process
  // then crashed the emulator/adb link right at the very end
  // ("adb: device offline" immediately after the last test finished).
  // Bisection isolated the crash to this file, and `ensureSemantics()` is
  // the only call of its kind anywhere in integration_test/. Since the
  // widget-tier test already covers the semantics-selection contract, this
  // flow keeps only the route-based assertions.
  testWidgets(
    'REGRESSION: tapping the in-page Passport tile lands on /passport '
    '(page↔navbar sync — nav-tile semantics-selection is covered at the '
    'widget tier; see home_inpage_branch_hop_test.dart)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Pre-condition: on Home.
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // Tap the in-page Passport preview tile (unique widget type, no localised
      // string — robust finder).
      final Finder passportTile = find.byType(PassportPreviewCard);
      expect(passportTile, findsOneWidget);
      await tester.ensureVisible(passportTile);
      await tester.tap(passportTile);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Page changed to the Passport branch...
      AppHarness.expectLocation(router, RouteNames.clientPassport);
      expect(
        find.byKey(const Key('client-branch-passport')),
        findsOneWidget,
        reason: 'the Passport page must be shown after the in-page tap',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 9 — REGRESSION (Rule 3b): home «Мій рейтинг» pill shows the REAL ──
  //             number served by GET /users/me/rating, not "—" ───────────────
  //
  // THE BUG THIS GUARDS
  // -------------------
  // The home-hub «Мій рейтинг» pill used to source its value from
  // `clientProfileProvider.clientRating` — an UNPOPULATED slice of the
  // `GET /users/me` profile body — so it always rendered "—", while the detail
  // window (`MyRatingScreen`) correctly showed the real number from
  // `myRatingProvider` (`GET /users/me/rating`). The fix re-wires `_StatPillsRow`
  // to watch `myRatingProvider`, so home and detail agree on the real number.
  //
  // The widget tier (home_hub_rating_pill_dedup_test.dart) proves the SOURCE
  // switch against an overridden provider. This flow proves the same fix over
  // the FULL production stack: real appRouter + real auth session → real
  // `myRatingProvider` → real `HttpRatingRepository` → real `UserControllerApi`
  // → an actual `GET /users/me/rating` HTTP round-trip against the fake backend.
  // The number-parity that was the whole bug is asserted end-to-end: the fake
  // backend's rating endpoint serves avgRating 4.7 and the home pill must render
  // "4.7" — NOT the "—" the old profile-summary source produced.
  //
  // NOT A NATIVE INTERACTION → no patrol flow is needed (no OS dialog, deep
  // link, notification, WebView, or biometric surface is touched).
  testWidgets(
    'REGRESSION: home «Мій рейтинг» pill renders the REAL avgRating (4.7) from '
    'GET /users/me/rating — the number-parity the source re-wire restored',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // The authoritative rating endpoint serves a real, non-null average so
        // the assertion is meaningful — a null here would render "—" and could
        // not distinguish the fixed wiring from the bug.
        ..myRatingAvgRating = 4.7
        ..myRatingReviewCount = 12;

      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      // Allow the stagger reveal + the GET /users/me/rating fetch to settle so
      // the resolved number is painted on the pill.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The pill must be the DATA widget (never the "—" empty form) and must
      // carry the real average straight off ClientRating.avgRating.
      final Finder pill = find.byType(MyRatingStatCard);
      expect(pill, findsOneWidget);
      expect(
        tester.widget<MyRatingStatCard>(pill).clientRating,
        4.7,
        reason:
            'the home pill value must come from GET /users/me/rating '
            '(ClientRating.avgRating) — the same source MyRatingScreen reads — '
            'not the unpopulated profile-summary clientRating slice',
      );

      // The rendered number is "4.7" (toStringAsFixed(1)) inside the pill, NOT
      // the "—" the old clientProfileProvider source produced. Scope the finder
      // to the pill so an unrelated "4.7" elsewhere could never false-pass.
      expect(
        find.descendant(of: pill, matching: find.text('4.7')),
        findsOneWidget,
        reason:
            'the home «Мій рейтинг» pill must render the real "4.7", the exact '
            'regression the source re-wire fixed (it used to show "—")',
      );
      expect(
        find.descendant(of: pill, matching: find.text('—')),
        findsNothing,
        reason:
            'the pill must NOT fall back to the "—" empty value when the rating '
            'endpoint serves a real average',
      );

      // The real HTTP round-trip actually happened — proves the pill is backed
      // by the rating endpoint, not a static profile field.
      expect(
        fb.getMyRatingCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the home pill must drive an actual GET /users/me/rating call — the '
            'authoritative source, distinct from GET /users/me',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
