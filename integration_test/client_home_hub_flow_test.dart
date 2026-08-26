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
//   6. Favorites and timeline show their empty states (backend 19.x not yet
//      wired — they are placeholder providers). The next-appointment card is
//      data-wired (Phase 225, `GET /bookings/me`) — it shows its OWN empty
//      state only when no CONFIRMED booking is seeded; see the dedicated
//      "live data + cancel" test below for the populated path.
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
// GET /clients/me/passport, GET /favorites/masters — not yet wired in
// FakeBackend (backend 19.x). Their providers return empty/null placeholders
// so the Hub shows empty states; the integration test asserts the
// empty-state keys to confirm this.
//
// GET /bookings/me (Phase 225), GET /users/me/rating, and (since the Phase
// 110 gap-closure pass below) GET /clients/me/timeline ARE wired — the
// next-appointment card, the «Мій рейтинг» stat pill, and the BEAUTY
// TIMELINE rail all render real FakeBackend data now. FakeBackend seeds ONE
// booking (`booking-1`, CONFIRMED, 7 days out) by default, so a flow that
// wants the next-appointment EMPTY state must explicitly flip
// `fb.bookingStatus` away from CONFIRMED first — see the "no CONFIRMED
// booking seeded" test below. `fb.timelineRows` defaults to EMPTY (a
// genuinely empty page from the wired endpoint, not a hard-coded
// placeholder) — see the "BEAUTY TIMELINE" tests near the end of this file
// for the populated-rail coverage.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/category_icons.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/features/rating/presentation/my_rating_screen.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// Scrolls the Home Hub body until [finder] is BUILT and on screen.
///
/// WHY EVERY BELOW-THE-FOLD ASSERTION MUST GO THROUGH THIS
/// -------------------------------------------------------
/// `_HomeHubBody` renders `ListView(children: [...])`, which is lazy: it builds
/// a `SliverList` whose children are instantiated on demand as the viewport
/// reaches them. On the 800×600 test surface — further reduced by the shell's
/// `ClientTopBar` and `ClientBottomNav` — everything from the favourites
/// section down is outside the viewport AND outside the default 250 px
/// `cacheExtent`, so those widgets are not in the element tree at all.
///
/// `findsNothing` for such a widget therefore means "not built yet", NOT "not
/// rendered by the app" — asserting on it without scrolling tests the viewport
/// height, not the screen. Measured at HEAD: `next_appointment_empty` is built,
/// `favorite_masters_empty` and `timeline_empty` are not; after one scroll all
/// three resolve.
Future<void> _scrollHubTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byType(HomeHubScreen),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();
}

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
      // The burger lives on the SHELL-owned ClientTopBar, not on HomeHubScreen,
      // and carries `Key('btn-menu-client')`. The old `home_hub_menu_button`
      // key was deliberately retired in 759149f ("3-tile quick-links +
      // master-style burger menu"), which re-shaped the hub burger to match the
      // master profile's `btn-menu-master`; `client_shell.dart::_configFor`
      // documents `btn-menu-client` as the preserved finder target. This
      // assertion was simply never updated — it is not a missing button.
      expect(
        find.byKey(const Key('btn-menu-client')),
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
      //
      // SCOPED ON PURPOSE (not a relaxed assertion). "BEAUTY PASSPORT" renders
      // TWICE on this screen, and both renders are correct:
      //   1. `PassportPreviewCard` — the in-page stat tile (the literal at
      //      passport_preview_card.dart:92), which is what this test is about;
      //   2. `ClientBottomNav` tab 4's label — `kBeautyPassportLabel`
      //      (client_bottom_nav.dart:32), rendered for every tab regardless of
      //      selection, and mounted on every CLIENT branch including Home.
      // They live in different visual regions (page body vs. bottom nav), so
      // this is the intended design, not a duplicate-render bug. An unscoped
      // `findsOneWidget` was asserting something the app never promised;
      // scoping to `PassportPreviewCard` is exactly what the reason string
      // below already claimed, and it can no longer be satisfied by the nav.
      expect(
        find.descendant(
          of: find.byType(PassportPreviewCard),
          matching: find.textContaining('BEAUTY PASSPORT'),
        ),
        findsOneWidget,
        reason:
            'PassportPreviewCard must render the "BEAUTY PASSPORT" brand literal '
            '(intentionally untranslated per product decision)',
      );

      // The timeline section is below the fold and lazily built — scroll it in
      // before asserting (see `_scrollHubTo`). Asserted AFTER the passport tile
      // so that tile is still on screen for its own assertion above.
      await _scrollHubTo(tester, find.byType(BeautyTimelineSection));
      expect(
        find.descendant(
          of: find.byType(BeautyTimelineSection),
          matching: find.textContaining('BEAUTY TIMELINE'),
        ),
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
  //
  // QA (Phase 225 live-data wiring): FakeBackend seeds `booking-1` CONFIRMED
  // by default, so the next-appointment card is NOT empty out of the box any
  // more (see the FAKE-BACKEND GAPS note above) — this fixture explicitly
  // flips it away from CONFIRMED so this test still proves the card's own
  // empty state, isolated from favorites/timeline's still-genuinely-
  // unwired empty states. The POPULATED path (default fixture) + the cancel
  // interaction are covered by the dedicated test right after this one.

  testWidgets(
    'next-appointment (no CONFIRMED booking seeded), favorites, and timeline '
    'show empty states',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // No upcoming booking: GET /bookings/me?status=CONFIRMED must come
        // back empty so nextAppointmentProvider resolves null.
        ..bookingStatus = 'COMPLETED';
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The Next-appointment section's empty-state key.
      expect(
        find.byKey(const Key('next_appointment_empty')),
        findsOneWidget,
        reason:
            'next-appointment section must show its empty state when no '
            'CONFIRMED booking is seeded (the endpoint itself is wired — '
            'Phase 225)',
      );

      // FavoriteMastersCard empty state key. Below the fold on the test surface
      // and lazily built, so it must be scrolled in first — see `_scrollHubTo`.
      await _scrollHubTo(
        tester,
        find.byKey(const Key('favorite_masters_empty')),
      );
      expect(
        find.byKey(const Key('favorite_masters_empty')),
        findsOneWidget,
        reason:
            'favorites section must show its empty state because the '
            'favorites endpoint (backend 19.1) is not yet wired',
      );

      // BeautyTimelineSection empty state key — likewise below the fold.
      // The endpoint IS wired (Phase 110) — FakeBackend's `timelineRows`
      // defaults to an empty list, so this is a genuinely empty page from
      // the real endpoint, not an unwired placeholder any more.
      await _scrollHubTo(tester, find.byKey(const Key('timeline_empty')));
      expect(
        find.byKey(const Key('timeline_empty')),
        findsOneWidget,
        reason:
            'timeline section must show its empty state when FakeBackend '
            'serves a genuinely empty page (default `timelineRows`)',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test 4b — QA (Phase 225, Step 2.7 Rule 3b): next-appointment card ─────
  //              renders LIVE booking data and cancelling from the card ──────
  //              updates it back to the empty state ──────────────────────────
  //
  // THE GAP THIS GUARDS
  // --------------------
  // The «Найближчий запис» card used to be a hardcoded `null` stub (permanent
  // empty state). It is now wired to `BookingRepository.getMyBookings` and its
  // «Скасувати» button now routes into the SAME shared `startBookingCancel`
  // helper the «Деталі запису» screen uses. Neither fact was proven end to
  // end anywhere: the widget tier stubs `onCancel` with a no-op, and the unit
  // tier (`next_appointment_provider_test.dart`) fakes the repository
  // directly rather than driving the real HTTP round trip a CLIENT actually
  // exercises. This flow closes both gaps over the REAL app + FakeBackend:
  //
  //   1. CLIENT logs in with the DEFAULT fixture (booking-1, CONFIRMED, 7
  //      days out) → the card renders POPULATED, not empty, with the real
  //      master/service/location the fake backend served.
  //   2. Tapping «Скасувати» on the CARD (not the detail screen) opens the
  //      SAME cancellation-note dialog `booking_detail_screen.dart` uses.
  //   3. Confirming calls `PATCH /bookings/booking-1/cancel` with the note.
  //   4. The card re-renders EMPTY — proving `nextAppointmentProvider` was
  //      genuinely invalidated and re-fetched from THIS call site (the newest
  //      entry in the cancel helper's invalidation fan-out), not just that a
  //      SnackBar or dialog closed.
  //
  // NOT A NATIVE INTERACTION → no patrol flow is needed (no OS dialog, deep
  // link, notification, WebView, or biometric surface is touched — this is a
  // plain in-app dialog + HTTP PATCH).
  // USER-LOCKED DECISION — the populated Next-appointment card now renders
  // the SAME read-only `BookingCard` widget «Мої записи» uses: "the card has
  // ONE affordance: open me" (see `booking_card.dart`'s library doc). It no
  // longer carries its own «Скасувати» trigger — that flow (dialog → PATCH →
  // card falls back to empty) now lives ONLY on «Деталі запису» and is
  // covered there by `booking_detail_screen.dart`'s own test suite (see the
  // retired `home_hub_cancel_wiring_test.dart`'s file header for the mapping
  // of which surface covers what). This test instead proves the two things
  // that ARE still specific to the Home Hub: the card renders LIVE booking
  // data through the shared widget, and tapping it opens «Деталі запису» —
  // the HIGHEST-RISK part of the cutover: `RouteNames.bookingDetail` is
  // nested under the CLIENT shell's Записи branch in production
  // (app_router.dart), while the Home Hub sits on a DIFFERENT branch. Driven
  // through the REAL `appRouter` (not a test-local stub), this proves a
  // cross-branch push lands on the detail screen AND that popping back
  // returns to the HOME HUB — the bottom nav stays on Головна, it never gets
  // silently left on Записи.
  testWidgets('next-appointment card renders LIVE booking data via the shared '
      'BookingCard, and tapping it opens «Деталі запису» — popping back '
      'returns to the Home Hub, not the Записи tab', (tester) async {
    // Default fixture: booking-1 is CONFIRMED, 7 days out — genuinely
    // upcoming, so this is the "no override needed" happy path.
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ── 1. Populated, not empty — real data rendered through the SAME ──
    //      shared BookingCard widget «Мої записи» uses.
    expect(
      find.byKey(const Key('next_appointment_populated')),
      findsOneWidget,
      reason:
          'the default FakeBackend fixture seeds an upcoming CONFIRMED '
          'booking, so the card must render POPULATED on a fresh login, '
          'never the permanent empty-state stub it used to be',
    );
    expect(find.byKey(const Key('next_appointment_empty')), findsNothing);
    expect(
      find.byType(BookingCard),
      findsOneWidget,
      reason:
          'the populated state renders the SAME shared BookingCard widget '
          '«Мої записи» uses — no Home-Hub-specific card class any more',
    );

    // i18n-finder-ok: fixture data from FakeBackend (master name / service),
    // not translated UI copy.
    expect(
      find.text('Софія Бондар'),
      findsOneWidget,
      reason: 'the card must show the REAL booked master name',
    );
    expect(
      find.text('Манікюр з покриттям'),
      findsOneWidget,
      reason: 'the card must show the REAL booked service name',
    );

    // No in-card action buttons any more — BookingCard "has ONE
    // affordance: open me".
    expect(find.byKey(const Key('next_appt_cancel_button')), findsNothing);
    expect(find.byKey(const Key('next_appt_reschedule_button')), findsNothing);

    // ── 2. Tap the card → «Деталі запису» for THIS booking. ───────────────
    await tester.tap(find.byType(BookingCard));
    await AppHarness.settle(tester);

    expect(
      find.byType(BookingDetailScreen),
      findsOneWidget,
      reason:
          'tapping the card must push «Деталі запису» for booking-1 — the '
          'card carries no buttons of its own any more',
    );
    // `nestedPushLocation` (not `expectShellLocation`) is the correct
    // resolver here: empirically, go_router's `push` grafts this leaf onto
    // the shell match of whichever branch is CURRENTLY ACTIVE (Home) rather
    // than resolving a fresh branch from the URL, even though
    // `bookingDetail` is statically declared under the Записи branch's own
    // route tree in app_router.dart — see [AppHarness.nestedPushLocation]'s
    // doc comment for exactly this shape.
    AppHarness.expectNestedPushLocation(
      router,
      '${RouteNames.clientBookings}/booking-1',
    );
    // The bottom nav is suppressed on the detail page itself (matches every
    // other pushed-detail route in the CLIENT shell).
    expect(find.byType(ClientBottomNav), findsNothing);

    // ── 3. Pop back → the HOME HUB, with Головна still the active tab. ────
    // This is the load-bearing assertion for the cross-branch-push risk:
    // `bookingDetail` is declared under the Записи branch in app_router.dart,
    // so a naive implementation could silently switch the active branch
    // when pushed from Home. It must not — popping must land back on
    // HomeHubScreen with the bottom nav's Головна tile still selected.
    router.pop();
    await AppHarness.settle(tester);

    expect(
      find.byType(HomeHubScreen),
      findsOneWidget,
      reason:
          'popping the detail screen (reached from the Home Hub) must '
          'return to the Home Hub, not the Записи list',
    );
    expect(
      find.byType(MyBookingsScreen),
      findsNothing,
      reason:
          'a cross-branch-push regression would leave the Записи branch '
          'active underneath the popped detail screen instead',
    );
    final ClientBottomNav nav = tester.widget<ClientBottomNav>(
      find.byType(ClientBottomNav),
    );
    expect(
      nav.activeIndex,
      kClientHomeBranch,
      reason:
          'the bottom nav must still show Головна selected — a '
          'cross-branch-push regression would leave it on Записи '
          '(kClientBookingsBranch) instead',
    );
  }, timeout: const Timeout(Duration(seconds: 45)));

  // ── Test 4c — Phase 228: server-side `partition=UPCOMING` resolves the ───
  //              production-shaped stale-elapsed scenario from ONE request ──
  //
  // THE CUTOVER THIS GUARDS
  // -------------------------
  // Phase 225 fixed a live production bug (an account with a pile of stale
  // elapsed CONFIRMED bookings blanking the «Найближчий запис» card) with a
  // `from`-bounded query plus a bounded CLIENT-SIDE page-forward scan capped
  // at 3 pages. Phase 228 retires that scan now that `GET /bookings/me`
  // supports `partition=UPCOMING`: the backend excludes every elapsed
  // CONFIRMED row BEFORE the response is built, so page 0 row 0
  // (`size: 1`) is the whole answer — this is the SAME scenario Test 4c used
  // to regression-guard, now proving the single-request replacement instead.
  //
  // The unit suite (`next_appointment_provider_test.dart`, group
  // "single-request partition cutover") already proves the provider's own
  // request shape and single-call resolution against a hand-scripted fake
  // repository — but that fake ALREADY behaves as if server-side filtering
  // happened, because it isn't actually implementing that filtering; it
  // cannot prove the CLIENT sends `partition=UPCOMING` on the wire, nor that
  // a backend which actually implements the Phase 28.1/28.2 predicate
  // resolves the same shape correctly. `FakeBackend.seedManyBookingsDataset`
  // + `FakeBackend.backendSupportsPartition`/`_partitionOf` (mobile-qa,
  // reused from `client_my_bookings_partition_flow_test.dart`) implement the
  // ACTUAL backend predicate, so the exact production shape — 6 elapsed
  // CONFIRMED rows, 1 genuinely upcoming — reaches the client over a REAL
  // `GET /bookings/me?partition=UPCOMING&...` request that the fake actually
  // filters, not one hand-picked per call.
  //
  // NOTE ON `from` / TIMEZONE: `FakeBackend.serverNow` (the fake's model of
  // the BACKEND's own clock, consulted by `_partitionOf`) defaults to
  // `kFixedNow` — the SAME instant the harness pins `clockProvider` to for
  // the app under test (`e2e_boot_policy.dart`). Every fixture below is
  // anchored relative to `kFixedNow`, never the real wall clock: an
  // anchor off `DateTime.now()` would silently drift a row into the wrong
  // partition the moment real time moves past `kFixedNow`, exactly the bug
  // `FakeBackend.serverNow`'s doc comment calls out. The device-ahead-of-Kyiv
  // `from`-derivation boundary itself stays covered at the unit tier
  // (`next_appointment_provider_test.dart`'s "Kyiv-day boundary" group,
  // which pins `clockProvider` directly and needs no HTTP round trip); this
  // flow only needs to prove `from=<today>` genuinely reaches the wire
  // alongside `partition`, which `_slicedBookingsPageEnvelope` does not
  // itself enforce (it has no `from` handling — see its doc comment) but
  // `lastMyBookingsQuery` still records regardless.
  //
  // NOT A NATIVE INTERACTION → no patrol flow needed (no OS dialog, deep
  // link, notification, WebView, or biometric surface is touched).
  testWidgets(
    'Phase 228: 6 stale-elapsed CONFIRMED rows plus 1 genuinely-upcoming row '
    'resolve the next-appointment card from a SINGLE partition-filtered '
    'request — the page-forward scan this cutover retires never fires',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;

      // 6 elapsed CONFIRMED rows (6..1 days before kFixedNow, ascending) + 1
      // genuinely upcoming CONFIRMED row (3 days after kFixedNow) — the exact
      // production shape Phase 225 fixed with a page-forward scan. Anchored
      // to kFixedNow (FakeBackend.serverNow's default), NEVER DateTime.now()
      // — see the file-level note above.
      final DateTime upcomingStart = kFixedNow.add(const Duration(days: 3));
      final List<Map<String, dynamic>> dataset = <Map<String, dynamic>>[
        for (int daysAgo = 6; daysAgo >= 1; daysAgo--)
          fb.datasetBookingRow(
            id: 'elapsed-$daysAgo',
            status: 'CONFIRMED',
            startsAt: kFixedNow.subtract(Duration(days: daysAgo)),
            duration: const Duration(minutes: 30),
          ),
        fb.datasetBookingRow(
          id: 'real-upcoming',
          status: 'CONFIRMED',
          startsAt: upcomingStart,
        ),
      ];
      fb.seedManyBookingsDataset(dataset);

      final int callsBeforeLogin = fb.getMyBookingsCalls;
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Exactly ONE request — the Phase 228 headline behaviour change. The
      // pre-228 provider needed 2 calls for this exact fixture shape (page 0
      // all-elapsed, page 1 the real row); server-side partition filtering
      // means there is nothing left to page forward through.
      expect(
        fb.getMyBookingsCalls - callsBeforeLogin,
        1,
        reason:
            'a regression to the retired page-forward scan would issue a '
            '2nd call here; the provider must resolve this shape from a '
            'single partition-filtered request',
      );

      // The card is POPULATED with the genuinely upcoming booking.
      expect(
        find.byKey(const Key('next_appointment_populated')),
        findsOneWidget,
        reason:
            'the real upcoming booking must be surfaced from the single '
            'partition-filtered request, not the permanent empty state the '
            'pre-Phase-225 bug rendered for this exact shape',
      );
      expect(find.byKey(const Key('next_appointment_empty')), findsNothing);

      // It is the RIGHT booking — the server excluded every elapsed row,
      // never a client-side skip picking around a wrong head row. The Home
      // Hub renders the SAME shared `BookingCard` widget «Мої записи» uses
      // (locked decision) — its `.booking` is the exact fetched [Booking],
      // no lossy NextAppointment DTO projection any more.
      final BookingCard card = tester.widget<BookingCard>(
        find.byType(BookingCard),
      );
      expect(
        card.booking.id,
        'real-upcoming',
        reason:
            'the card must resolve to the genuinely upcoming row — never '
            'one of the 6 elapsed CONFIRMED rows the server excludes via '
            'partition=UPCOMING',
      );
      expect(card.booking.startAt, upcomingStart);

      // `partition` genuinely reached the wire — dropping it would silently
      // regress to an unfiltered/status-only scan (Spring drops an
      // unrecognised param rather than 400ing).
      expect(fb.lastMyBookingsQuery?['partition'], 'UPCOMING');
      // The legacy `status` still travels alongside `partition` — the same
      // Phase 227 rollout safety valve `BookingTabX`'s file header
      // documents, reused verbatim by this cutover (see
      // `BookingRepository.getMyBookings`'s doc for the precedence rule).
      expect(fb.lastMyBookingsQuery?['status'], <String>['CONFIRMED']);

      // `from` genuinely reached the wire (not just the mapped repository
      // argument the unit suite observes), alongside `partition` — kept even
      // though `partition` already excludes elapsed rows, because `from` is
      // day-granular and `partition` is instant-granular (see
      // `home_hub_notifier.dart`'s doc comment). `today` is derived from the
      // HARNESS's injected `kFixedNow` via `clockProvider` — NOT the real
      // device clock; `toBeauticaTime` mirrors exactly what the provider
      // itself does to turn that instant into the Europe/Kyiv calendar day.
      final DateTime today = dateOnly(toBeauticaTime(kFixedNow));
      expect(fb.lastMyBookingsQuery?['from'], toApiDate(today));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

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
        // Bug condition: authoritative FKs present, denormalized name absent.
        //
        // BOTH FKs must be seeded. `_resolveCityName`
        // (home_hub_notifier.dart:124) bails to '' unless `cityId` AND
        // `oblastId` are non-null, because the taxonomy lookup goes through
        // `cityListProvider(oblastId)` — the city list is fetched PER OBLAST
        // (`GET /locations/oblasts/{oblastId}/cities`), so a cityId alone is
        // not resolvable by construction. `FakeBackend.clientOblastId` starts
        // null, and this fixture previously seeded only `clientCityId`, so the
        // lookup short-circuited and the card fell to its placeholder — the
        // test failed for a missing fixture field, never reaching the
        // regression it guards. Seeding 'oblast-kyiv' matches the seeded
        // cities route, which returns city 'city-kyiv' named 'Київ'.
        ..clientOblastId = 'oblast-kyiv'
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

  // ── Test 9 — hub → «Мій рейтинг» → back, end to end ──────────────────────
  //
  // WHY THIS EXISTS (QA, house-header migration)
  // --------------------------------------------
  // Test 5 above only asserts the stat pill RENDERS; Test 6 only asserts the
  // NEGATIVE (an INDEPENDENT_MASTER never reaches /rating). Nothing in this
  // suite ever TAPPED the pill and came back — the hub → /rating → back edge
  // was untraversed end to end, even though
  // `home_hub_screen_test.dart` explicitly defers to this file for it
  // ("navigation correctness through GoRouter is covered by
  // client_home_hub_flow_test.dart"). That deferral was stale.
  //
  // It matters now because MyRatingScreen's back affordance changed widget
  // type — a Material `AppBar` `IconButton` became a `NeumorphicIconButton`
  // inside the shared `VelvetTopBar`. The widget-tier pop test drives a
  // synthetic two-route GoRouter; it cannot prove the pop behaves inside the
  // REAL router, where `/rating` is a TOP-LEVEL route pushed imperatively ON
  // TOP of the CLIENT StatefulShellRoute. That push/pop shape is precisely the
  // one this repo has been bitten by before (an ImperativeRouteMatch is
  // excluded from `currentConfiguration.fullPath`), so it is asserted through
  // AppHarness.location, which unwraps it.
  //
  // QA follow-up (wordmark house-header revision): the widget tier
  // (`my_rating_screen_test.dart`) already pins that the centred slot renders
  // the "beautica" wordmark instead of the localised "МІЙ РЕЙТИНГ" title, but
  // only against a synthetic pump. This flow re-asserts BOTH sides of that
  // swap (wordmark present, old title glyph absent) scoped inside the REAL
  // `MyRatingScreen` subtree mounted by the production router, so a
  // regression that only shows up under the real `AppHarness`/GoRouter stack
  // (e.g. a route-level rebuild reintroducing the old `title:`-only render)
  // cannot hide behind a widget-tier false pass.
  testWidgets(
    'hub → «Мій рейтинг» → back: the stat pill opens MyRatingScreen under the '
    'shared VelvetTopBar and its back arrow returns to /home',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..myRatingAvgRating = 4.7
        ..myRatingReviewCount = 12
        // QA (Rule 3b): a single bucket, deliberately not covering all five
        // stars — proves the REAL `GET /users/me/rating` round-trip both
        // resolves the 5★ bucket by its `rating` value AND zero-fills the
        // other four slots (the repository's default-to-0 branch), not a
        // synthetic ClientRating built in a widget test. The count (23) is
        // chosen to be unambiguous against the fixed 5/4/3/2/1 star-number
        // labels `RatingSummaryCard` always renders in the same column.
        ..myRatingDistribution = <Map<String, dynamic>>[
          <String, dynamic>{'rating': 5, 'count': 23},
        ];
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ACT 1 — tap the real pill (own widget type, not a framework widget).
      final Finder pill = find.byType(MyRatingStatCard);
      await tester.ensureVisible(pill);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(pill);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      AppHarness.expectLocation(router, RouteNames.myRating);
      expect(find.byType(MyRatingScreen), findsOneWidget);

      // The house header is what the user sees on arrival — asserted inside
      // the MyRatingScreen subtree so the hub's own chrome cannot satisfy it.
      expect(
        find.descendant(
          of: find.byType(MyRatingScreen),
          matching: find.byType(VelvetTopBar),
        ),
        findsOneWidget,
        reason: 'the rating screen must arrive wearing the house header',
      );
      expect(
        find.descendant(
          of: find.byType(MyRatingScreen),
          matching: find.byType(AppBar),
        ),
        findsNothing,
        reason:
            'the Material AppBar must be gone in the real app, not just '
            'in the widget test',
      );
      // The screen really loaded its data over the fake backend, so the header
      // is being asserted on a fully-rendered screen, not an empty shell.
      expect(find.byKey(const Key('my_rating_display')), findsOneWidget);

      // QA (Rule 3b) — the rated table actually renders over the REAL HTTP
      // round-trip, not just a synthetic ClientRating (that contract is
      // already pinned at the widget tier in my_rating_screen_test.dart).
      // Scoped to the RatingSummaryCard subtree throughout so nothing
      // elsewhere on the hub/screen chrome could false-pass any assertion.
      final Finder summaryCard = find.byType(RatingSummaryCard);
      expect(
        summaryCard,
        findsOneWidget,
        reason:
            'MyRatingScreen must render the shared RatingSummaryCard table '
            'once GET /users/me/rating resolves to a non-null avgRating',
      );

      // The per-star bucket count served by the fake backend's real HTTP
      // response must reach the screen through the FULL stack: real
      // UserControllerApi → HttpRatingRepository._distributionFromBuckets →
      // ClientRating.distribution → RatingSummaryCard's distribution table.
      // "23" cannot collide with the fixed 5/4/3/2/1 star-number labels the
      // card always renders in the adjacent column, so this proves the
      // COUNT column specifically, not just that some digit is on screen.
      expect(
        find.descendant(of: summaryCard, matching: find.text('23')),
        findsOneWidget,
        reason:
            'the 5★ bucket\'s real wire count (23) must render in the '
            'distribution table — proves the fold survives the real HTTP '
            'round-trip, not only a synthetic provider override',
      );

      // The locked product rule, re-asserted end to end: a CLIENT never sees
      // individual comments about them, on ANY provider-served payload shape
      // — the widget tier already pins this against a synthetic ClientRating
      // (my_rating_screen_test.dart); this proves it survives the real
      // GET /users/me/rating round-trip too.
      expect(
        find.byType(ReviewCard),
        findsNothing,
        reason:
            'ReviewCard/comment content must never render on the real '
            'MyRatingScreen — the client sees only the aggregate table, '
            'never individual master/salon comments about them',
      );

      // The centred slot renders the "beautica" wordmark, not the localised
      // "МІЙ РЕЙТИНГ" title — asserted on the REAL router-mounted screen, not
      // a synthetic widget-test pump (see `my_rating_screen_test.dart` for the
      // widget-tier twin of this assertion).
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MyRatingScreen)),
      );
      expect(
        find.descendant(
          of: find.byType(MyRatingScreen),
          matching: find.text('beautica'),
        ),
        findsOneWidget,
        reason:
            'the real MyRatingScreen must render the "beautica" wordmark in '
            'its house header',
      );
      expect(
        find.descendant(
          of: find.byType(MyRatingScreen),
          matching: find.text(l10n.myRatingTitle),
        ),
        findsNothing,
        reason:
            'the old localised "МІЙ РЕЙТИНГ" title must NOT render visually '
            'anywhere under the real MyRatingScreen — regressing to it (e.g. '
            'a route-level rebuild dropping titleWidget) is exactly the '
            'failure this flow-level assertion catches',
      );

      // ACT 2 — the NEW NeumorphicIconButton back arrow must pop the push.
      await tester.tap(find.byKey(const Key('my_rating_back_button')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(
        find.byType(MyRatingScreen),
        findsNothing,
        reason:
            'the back arrow must POP the imperatively-pushed /rating route — '
            'a screen left mounted over the shell is the failure mode a '
            'widget-tier pop test cannot see',
      );
      expect(
        find.byType(HomeHubScreen),
        findsOneWidget,
        reason: 'the client lands back on the hub, not a blank shell branch',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test N — mobile-qa gap-closure (Phase 110 / Step 2.7 Rule 3b) ────────
  //              BEAUTY TIMELINE rail: populated rendering, sort, and the ────
  //              bookingId tap-to-navigate / inert-when-absent contract ─────
  //
  // The widget tier (home_hub_screen_test.dart) and the data-layer unit
  // tier (timeline_repository_test.dart / timeline_mapper_test.dart) each
  // prove ONE link of this chain in isolation with fakes/mocks. Neither
  // exercises the REAL journey end to end: a CLIENT's real HTTP round trip
  // through FakeBackend, the real TimelineMapper sort, and the real
  // go_router `context.push` navigating to «Деталі запису». This is exactly
  // the shape Step 2.7 Rule 3b requires for a change that touches a screen +
  // provider/repository wiring + API contract + navigation.

  testWidgets(
    'BEAUTY TIMELINE rail renders populated tiles most-recent-first from '
    'FakeBackend data (proves the client-side re-sort, not wire order)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // Isolate the timeline from the next-appointment card so only ONE
        // BookingCard-shaped section is on screen (matches Test 4's "no
        // CONFIRMED booking seeded" fixture flip).
        ..bookingStatus = 'COMPLETED'
        // Deliberately seeded ASCENDING (oldest first) — the backend already
        // orders DESC in production, but TimelineMapper.fromDtoList
        // re-sorts client-side regardless (see its file header) and must
        // never simply trust wire order. If that re-sort were ever dropped,
        // the rail would render these in THIS ascending order and the dx
        // assertions below would fail.
        ..timelineRows = <Map<String, dynamic>>[
          <String, dynamic>{
            'bookingId': null,
            'categoryKey': 'PEDICURE',
            'categoryName': 'Педикюр',
            'date': '2026-04-02',
            'masterId': 'master-1',
            'serviceName': 'Класичний педикюр',
          },
          <String, dynamic>{
            'bookingId': null,
            'categoryKey': 'BROW',
            'categoryName': 'Брови',
            'date': '2026-05-12',
            'masterId': 'master-1',
            'serviceName': 'Корекція брів',
          },
          <String, dynamic>{
            'bookingId': null,
            'categoryKey': 'NAIL_SERVICE',
            'categoryName': 'Манікюр',
            'date': '2026-06-18',
            'masterId': 'master-1',
            'serviceName': 'Класичний манікюр',
          },
        ];
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await _scrollHubTo(tester, find.byKey(const Key('timeline_rail')));

      // i18n-finder-ok: these are FakeBackend fixture category names, not
      // translated UI copy — asserting their horizontal order, not content.
      final double manicureX = tester.getTopLeft(find.text('Манікюр')).dx;
      final double browX = tester.getTopLeft(find.text('Брови')).dx;
      final double pedicureX = tester.getTopLeft(find.text('Педикюр')).dx;

      expect(
        manicureX,
        lessThan(browX),
        reason:
            'the most recent procedure (18 Jun) must render leftmost — a '
            'regression to wire order would put Педикюр (2 Apr) first '
            'instead',
      );
      expect(
        browX,
        lessThan(pedicureX),
        reason:
            'the middle-dated procedure (12 May) must render before the '
            'oldest (2 Apr)',
      );

      expect(
        fb.getTimelineCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the rail must be backed by a real GET /clients/me/timeline '
            'call, not a hard-coded fixture',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'tapping a BEAUTY TIMELINE tile with a bookingId opens «Деталі запису» — '
    'a tile with no bookingId is inert (no navigation, no crash)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..timelineRows = <Map<String, dynamic>>[
          // No bookingId at all — the wire shape for a completed procedure
          // whose source booking cannot be resolved server-side. Must
          // render on the rail but stay non-tappable (never coerced to '').
          <String, dynamic>{
            'bookingId': null,
            'categoryKey': 'BROW',
            'categoryName': 'Брови',
            'date': '2026-05-12',
            'masterId': 'master-1',
            'serviceName': 'Корекція брів',
          },
          // Reuses "booking-1" — the ONLY seeded booking with a wired
          // GET /bookings/:id route (`_wireBookingDetail` in
          // fake_backend.dart uses a CONCRETE path; the DioAdapter mock has
          // no path-template matching).
          <String, dynamic>{
            'bookingId': 'booking-1',
            'categoryKey': 'NAIL_SERVICE',
            'categoryName': 'Манікюр',
            'date': '2026-06-18',
            'masterId': 'master-1',
            'serviceName': 'Класичний манікюр',
          },
        ];
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await _scrollHubTo(tester, find.byKey(const Key('timeline_rail')));

      // ── 1. The bookingId-less tile renders but is INERT. ────────────────
      expect(
        find.text('Брови'),
        findsOneWidget,
        reason: 'the no-bookingId row must still render on the rail',
      );
      expect(
        find.byKey(const Key('timeline_tile_booking-1')),
        findsOneWidget,
        reason: 'the bookingId-carrying row must render as a keyed InkWell',
      );
      // `warnIfMissed: false` — this is a DELIBERATE inert-tile tap (no
      // GestureDetector/InkWell exists on this branch of `_TimelineNode`),
      // not a scroll-clipping miss. Mirrors `TapCalendarDay`'s documented
      // distinction (test/helpers/pump_app.dart) for the same shape of
      // assertion.
      await tester.tap(find.text('Брови'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.byType(BookingDetailScreen),
        findsNothing,
        reason:
            'a timeline row with no bookingId must never navigate — '
            'TimelineMapper never coerces a missing id to "" (see '
            'timeline_mapper.dart\'s header), and BeautyTimelineSection only '
            'wraps a tile in InkWell when bookingId is non-null/non-empty '
            '(beauty_timeline_section.dart\'s _TimelineNode)',
      );

      // ── 2. The bookingId-carrying tile navigates to «Деталі запису». ────
      await tester.tap(find.byKey(const Key('timeline_tile_booking-1')));
      await AppHarness.settle(tester);

      expect(
        find.byType(BookingDetailScreen),
        findsOneWidget,
        reason:
            'tapping a timeline tile whose bookingId is set must push '
            '«Деталі запису» via context.push '
            '(BeautyTimelineSection.onOpenBooking → '
            'RouteNames.bookingDetail)',
      );
      // `expectNestedPushLocation` (not `expectLocation`) — `push` grafts
      // this leaf onto the shell match of whichever branch is CURRENTLY
      // ACTIVE (Home), the same shape the next-appointment card's own
      // navigation test above documents.
      AppHarness.expectNestedPushLocation(
        router,
        '${RouteNames.clientBookings}/booking-1',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test N+1 — mobile-qa (Phase 110 Part 2 / Step 2.7 Rule 3b): the rail ──
  //              renders category icons via the shared `categoryIconFor` ────
  //              resolver, on the REAL rendered tree — for both the ─────────
  //              known-slug path AND the unknown-slug/name-fallback path ────
  //
  // WHY THIS EXISTS
  // ----------------
  // `category_icons_test.dart` (mobile-qa, closes a mobile-security LOW)
  // already proves `categoryIconFor` itself is total and adversary-safe as a
  // pure function. It does NOT prove the rail actually WIRES that function's
  // output into the rendered `AppIcon` for real FakeBackend-served rows —
  // that wiring is `beauty_timeline_section.dart`'s `_TimelineNode.build`,
  // one call site, previously untested end to end (the widget tier only
  // pumps `BeautyTimelineSection` directly with hand-built `TimelineEntry`
  // fixtures whose `categoryKey` never round-trips through the real
  // `GET /clients/me/timeline` → `TimelineMapper` → provider chain). This
  // flow drives that chain for real and asserts the rendered `AppIcon.asset`
  // against an INDEPENDENTLY computed expectation — never trusting the
  // resolver's own output as its own proof.
  testWidgets(
    'BEAUTY TIMELINE rail wires the shared categoryIconFor resolver into '
    'the rendered AppIcon for both a known categoryKey and an unknown-key/'
    'name-fallback row',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..timelineRows = <Map<String, dynamic>>[
          // Known, registered slug — Stage 1 of the resolver must win.
          <String, dynamic>{
            'bookingId': null,
            'categoryKey': 'INJECTION_COSMETOLOGY',
            'categoryName': "Ін'єкційна косметологія",
            'date': '2026-06-20',
            'masterId': 'master-1',
            'serviceName': 'Біоревіталізація',
          },
          // Legacy/unregistered slug ("PEDICURE" is not in _fromKey's
          // switch — the real registered slug is "PODOLOGY") paired with a
          // matching Ukrainian name, so the resolver must fall through to
          // Stage 2 and land on the Podology asset, not the generic
          // fallback — the exact fallthrough `category_icons_test.dart`
          // pins in isolation, now proven wired end to end.
          <String, dynamic>{
            'bookingId': null,
            'categoryKey': 'PEDICURE',
            'categoryName': 'Педикюр',
            'date': '2026-05-02',
            'masterId': 'master-1',
            'serviceName': 'Класичний педикюр',
          },
        ];
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await _scrollHubTo(tester, find.byKey(const Key('timeline_rail')));

      // i18n-finder-ok: FakeBackend fixture category names, not translated
      // UI copy.
      final AppIcon injectionIcon = _appIconForTile(
        tester,
        caption: "Ін'єкційна косметологія",
      );
      expect(
        injectionIcon.asset,
        categoryIconFor(
          categoryKey: 'INJECTION_COSMETOLOGY',
          categoryName: "Ін'єкційна косметологія",
        ),
        reason:
            'the rendered AppIcon for the known-slug row must carry the '
            'EXACT asset path categoryIconFor resolves for that same input '
            '— a hard-coded/guessed asset in _TimelineNode would silently '
            'desync from the resolver and this comparison would fail',
      );
      // Independently pin the specific asset too — belt and braces against
      // both sides of the comparison drifting together.
      expect(
        injectionIcon.asset,
        'assets/icons/category_injection_cosmetology.svg',
      );
      expect(
        injectionIcon.size,
        36.0,
        reason:
            'Phase 110 Part 2 grew the medallion glyph 26 → 36dp — the '
            'rendered AppIcon must carry the new size, not the retired one',
      );

      final AppIcon pedicureIcon = _appIconForTile(tester, caption: 'Педикюр');
      expect(
        pedicureIcon.asset,
        categoryIconFor(categoryKey: 'PEDICURE', categoryName: 'Педикюр'),
        reason:
            'the unregistered "PEDICURE" slug must resolve through the '
            'REAL name-fallback stage (landing on Podology), not the '
            'generic cosmetology fallback — proves the fallthrough is '
            'actually reachable on real wire data, not merely declared',
      );
      expect(
        pedicureIcon.asset,
        'assets/icons/category_podology.svg',
        reason:
            'if this ever regresses to the generic fallback '
            '(category_cosmetology.svg), the assertion above would still '
            'pass (both sides drift together) — this literal pin catches '
            'exactly that class of regression',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // ── Test N+2 — mobile-qa (Phase 110 Part 2 / Step 2.7 Rule 3b): the ───────
  //              long category caption genuinely WRAPS to 2 lines on the ────
  //              real rendered tree, never ellipsis-truncates ───────────────
  //
  // WHY THIS EXISTS
  // ----------------
  // The overflow-guard suite (`home_hub_overflow_test.dart`) proves the rail
  // doesn't RenderFlex-overflow at this caption length; it never proves the
  // caption's own TEXT is fully visible rather than silently ellipsis-
  // clipped (an ellipsis clip renders a perfectly valid, non-overflowing
  // layout — the failure mode this test exists to catch is invisible to an
  // overflow guard). This flow measures the REAL rendered tile width (not a
  // hard-coded constant — `_tileWidth` is file-private and unreachable from
  // here) and independently lays out the full caption string at that exact
  // width with the SAME style/text-scaler the widget uses, asserting Flutter
  // itself reports no overflow AND that 2 lines were actually used (not
  // fitting trivially on 1) — proving the tile is genuinely exercising the
  // Phase 110 Part 2 two-line contract, not merely fitting by coincidence.
  testWidgets(
    'BEAUTY TIMELINE rail: the long caption «Ін\'єкційна косметологія» wraps '
    'to 2 lines and is never ellipsis-truncated',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..timelineRows = <Map<String, dynamic>>[
          <String, dynamic>{
            'bookingId': null,
            'categoryKey': 'INJECTION_COSMETOLOGY',
            'categoryName': "Ін'єкційна косметологія",
            'date': '2026-06-20',
            'masterId': 'master-1',
            'serviceName': 'Біоревіталізація',
          },
        ];
      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await _scrollHubTo(tester, find.byKey(const Key('timeline_rail')));

      const String caption = "Ін'єкційна косметологія";
      final Finder captionFinder = find.descendant(
        of: find.byKey(const Key('timeline_rail')),
        matching: find.text(caption),
      );
      expect(
        captionFinder,
        findsOneWidget,
        reason: 'the long-caption fixture row must render on the rail',
      );

      // The tile's own tight-width SizedBox is the caption's real layout
      // constraint (see beauty_timeline_section.dart's `_tileWidth` doc
      // comment) — the closest ancestor SizedBox of the caption Text.
      final Finder tileBox = find
          .ancestor(of: captionFinder, matching: find.byType(SizedBox))
          .first;
      final double measuredTileWidth = tester.getSize(tileBox).width;

      final Text captionWidget = tester.widget<Text>(captionFinder);
      final TextPainter probe = TextPainter(
        text: TextSpan(text: caption, style: captionWidget.style),
        textDirection: TextDirection.ltr,
        maxLines: captionWidget.maxLines,
        textScaler: MediaQuery.textScalerOf(tester.element(captionFinder)),
      )..layout(maxWidth: measuredTileWidth);

      expect(
        probe.didExceedMaxLines,
        isFalse,
        reason:
            'laying out the FULL caption string at the ACTUAL measured tile '
            'width ($measuredTileWidth) with the widget\'s own maxLines '
            '(${captionWidget.maxLines}) must fit — a truncation regression '
            '(e.g. maxLines reverting to 1, or the tile shrinking back '
            'toward 84dp) would make this exceed and go red',
      );
      expect(
        probe.computeLineMetrics().length,
        2,
        reason:
            'this specific caption is the documented binding case that '
            'NEEDS 2 lines at the current tile width — 1 line here would '
            'mean the width grew enough to no longer exercise the Part 2 '
            'wrap contract at all',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

/// Returns the [AppIcon] rendered inside the BEAUTY TIMELINE tile whose
/// caption text is [caption]. Scopes the descendant search to the tile's
/// own tight-width `SizedBox` wrapper (the closest ancestor `SizedBox` of
/// the caption `Text` — see `beauty_timeline_section.dart`'s `_tileWidth`
/// doc comment) so a medallion icon from a DIFFERENT tile can never
/// false-satisfy this lookup.
AppIcon _appIconForTile(WidgetTester tester, {required String caption}) {
  final Finder captionFinder = find.descendant(
    of: find.byKey(const Key('timeline_rail')),
    matching: find.text(caption),
  );
  expect(
    captionFinder,
    findsOneWidget,
    reason: 'fixture bug: caption "$caption" must render exactly once',
  );
  final Finder tileBox = find
      .ancestor(of: captionFinder, matching: find.byType(SizedBox))
      .first;
  final Finder iconFinder = find.descendant(
    of: tileBox,
    matching: find.byType(AppIcon),
  );
  expect(
    iconFinder,
    findsOneWidget,
    reason: 'the tile for caption "$caption" must render exactly one AppIcon',
  );
  return tester.widget<AppIcon>(iconFinder);
}
