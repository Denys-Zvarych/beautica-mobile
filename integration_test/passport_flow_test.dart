// Phase 13.8 — E2E: CLIENT BEAUTY PASSPORT tab flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/passport/...) proves the PassportScreen and its
// PassportCard in isolation with mocked providers. The client-shell flow
// (client_shell_flow_test.dart) proves branch HOPPING in general. Neither
// exercises the REAL journey to the live PassportScreen: a CLIENT logging in
// through the real login form against the fake backend, hopping to the BEAUTY
// PASSPORT tab (branch index 4), and seeing the REAL PassportScreen render
// (Phase 13.8 replaced the index-4 placeholder with PassportScreen).
//
// This flow boots the REAL app via AppHarness (FakeBackend socket,
// FakeSecureStorage, fixed clock, overflow guard) and drives:
//
//   1. CLIENT login → lands on /home.
//   2. Tap the passport tab (client-nav-tile-4) → router at /passport, the real
//      PassportScreen mounted (keyed `client-branch-passport`).
//   3. The real HttpPassportRepository calls GET /clients/me/passport; the
//      FakeBackend serves the EMPTY passport body (bookingsConsidered 0), so
//      the screen renders its encouraging EMPTY variant (CTA present).
//   4. With a POPULATED body on the same route, the same journey renders the
//      derived document card (chips + budget ceiling) instead.
//
// WHY BOTH VARIANTS ARE REQUIRED HERE (Phase 13.8 wire-up regression)
// -------------------------------------------------------------------
// This flow used to assert the empty-state CTA and NOTHING else, with a header
// comment declaring the always-empty placeholder repository to be the expected
// behaviour. It therefore passed ON the bug: the screen showed every client the
// empty state forever and the E2E called that a success. An empty-only E2E
// cannot distinguish "correctly empty" from "structurally incapable of being
// anything else" — so the populated case below is the load-bearing one, and
// `fb.getPassportCalls` pins that the endpoint is genuinely hit rather than
// short-circuited in the data layer.
//
// NO PATROL FLOW NEEDED: this journey involves no native interaction (no OS
// permission dialog, deep link, FCM, WebView, biometric) — only in-app
// navigation and Riverpod state — so a standard integration_test flow is the
// correct (and sufficient) tier. The FLAG_SECURE acquire/release contract is
// covered at the widget tier (passport_screen_test.dart) where the native plugin
// is kDebugMode-guarded.
//
// FAKE-BACKEND NOTE: GET /clients/me/passport (backend 19.5) IS wired in
// FakeBackend and defaults to the empty-passport body (`FakeBackend.passportBody`,
// `bookingsConsidered: 0`), so the screen shows the empty state. The flow asserts
// the empty-state CTA key. Set `fb.passportBody` to serve a populated passport.
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders. Raw Ukrainian
// text appears in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_table.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// Derived values served on the wire by [_populatedPassportBody] and asserted
/// as rendered chips. Declared ONCE so the fixture and its assertions cannot
/// drift apart, and so the finders read the payload rather than re-typing it —
/// these are BACKEND DATA, never AppLocalizations copy, so they stay identical
/// when EN ships (see the `i18n-finder-ok` notes at the assertion sites).
const List<String> _wireProcedures = <String>['Манікюр', 'Брови', 'Педикюр'];
const List<String> _wireDistricts = <String>['Центр', 'Сихів', 'Франківський'];

/// The budget ceiling on the wire; the screen renders it through
/// `passportBudgetCeiling`.
const int _wireBudgetMax = 800;

/// A POPULATED `GET /clients/me/passport` body. Every value is deliberately
/// distinguishable from the empty body — non-empty chip lists, a non-null band,
/// a non-zero `bookingsConsidered` — so an assertion below cannot be satisfied
/// by the empty payload the flow previously (and only) exercised.
Map<String, dynamic> _populatedPassportBody() => <String, dynamic>{
  'favoriteProcedures': _wireProcedures,
  'favoriteDistricts': _wireDistricts,
  'budget': <String, dynamic>{
    'avg': 600,
    'min': 400,
    'max': _wireBudgetMax,
    'currency': 'UAH',
  },
  'bookingsConsidered': 7,
};

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT taps the passport tab → the real PassportScreen renders its EMPTY '
    'variant when the backend returns an empty passport',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // Hop to the BEAUTY PASSPORT tab (flanking tile index 4).
      await tester.tap(find.byKey(const Key('client-nav-tile-4')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Router moved to /passport, and the REAL PassportScreen is mounted —
      // a single ClientShell + bottom nav survive (goBranch, not push).
      AppHarness.expectLocation(router, RouteNames.clientPassport);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason: 'exactly one ClientShell must remain after hopping to passport',
      );
      expect(find.byType(ClientBottomNav), findsOneWidget);
      expect(
        find.byType(PassportScreen),
        findsOneWidget,
        reason:
            'the index-4 branch must mount the REAL PassportScreen '
            '(Phase 13.8 replaced the placeholder)',
      );
      // The screen carries the stable branch key the placeholder used to expose.
      expect(
        find.byKey(const Key('client-branch-passport')),
        findsOneWidget,
        reason: 'PassportScreen must carry the client-branch-passport key',
      );

      // The endpoint was genuinely called — the assertion the pre-wire-up
      // version of this flow could not make, because the placeholder
      // repository resolved without any network at all.
      expect(
        fb.getPassportCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the passport tab must hit GET /clients/me/passport — a screen '
            'that renders without calling the endpoint is the shipped bug',
      );

      // Empty body (bookingsConsidered 0) ⇒ the encouraging EMPTY variant with
      // its CTA, and NO populated document card.
      expect(
        find.byKey(const Key('passport_find_master_button')),
        findsOneWidget,
        reason:
            'an empty backend payload renders the empty-state CTA — EARNED '
            'from the wire, not hardcoded',
      );
      expect(find.byType(PassportCard), findsNothing);
      expect(find.byKey(const Key('passport_error_state')), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'CLIENT with derived history sees the POPULATED passport card, not the '
    'empty CTA',
    (tester) async {
      // THE LOAD-BEARING E2E CASE. This is the journey the shipped bug broke
      // end to end: a real client with completed bookings tapping the passport
      // tab and being told their passport is empty. It exercises the whole
      // chain the widget suite stubbed out — Dio → ClientControllerApi →
      // HttpPassportRepository → PassportMapper → passportProvider → screen.
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..passportBody = _populatedPassportBody();
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('client-nav-tile-4')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientPassport);

      expect(fb.getPassportCalls, greaterThanOrEqualTo(1));

      // The derived document card, with the values that came off the wire.
      expect(
        find.byType(PassportCard),
        findsOneWidget,
        reason:
            'a populated payload must render the passport card — rendering '
            'the empty state here is the Phase 13.8 defect',
      );
      // Chips are asserted against the SAME constants the fake backend served,
      // so the fixture and the expectation cannot drift. They are backend data,
      // not UI copy, hence locale-proof — unlike the l10n-keyed budget label
      // below.
      // i18n-finder-ok: values come from the wire fixture above, never AppLocalizations.
      for (final String chip in <String>[
        ..._wireProcedures,
        ..._wireDistricts,
      ]) {
        expect(
          find.text(chip),
          findsOneWidget,
          reason: 'derived chip "$chip" from the wire payload must render',
        );
      }

      // The budget ceiling comes through the mapper's num → double widening and
      // the screen's renderableWholePrice gate.
      final AppLocalizations l10n = await _uk();
      expect(
        find.text(l10n.passportBudgetCeiling(_wireBudgetMax)),
        findsOneWidget,
      );

      // Neither of the two non-data states may appear.
      expect(
        find.byKey(const Key('passport_find_master_button')),
        findsNothing,
        reason:
            'a client WITH history must never be shown the empty-passport CTA',
      );
      expect(find.text(l10n.passportEmptyTitle), findsNothing);
      expect(find.byKey(const Key('passport_error_state')), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'the passport empty-state CTA navigates the CLIENT to the search tab',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('client-nav-tile-4')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientPassport);

      // Tapping «Знайти майстра» routes to the discovery (search) tab.
      await tester.tap(find.byKey(const Key('passport_find_master_button')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, RouteNames.clientSearch);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason: 'the CTA hop stays inside the client shell (goBranch)',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
