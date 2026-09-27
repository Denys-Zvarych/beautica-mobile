// mobile-qa (2026-09-05) — E2E: the SALON_ADMIN's own «Профіль» tab
// (Phase 21.16), end to end, through the REAL router, the REAL post-login
// landing, the REAL `salonAdminOnlyGuard` and the REAL `GET /users/me` +
// `GET /salons/{salonId}` + locality-cascade reads.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// Phase 21.16 shipped a new SCREEN, a new ROUTE (`/profile/admin`) and a new
// ROLE GUARD, and swapped a placeholder on a surface the user reaches by
// tapping a bottom-nav destination after signing in. That is a screen + route
// + provider↔repository change three times over, so widget tests alone do not
// satisfy the gate. What the widget tier CANNOT reach:
//
//   • `admin_own_profile_screen_test.dart` overrides `clientEditProfileProvider`
//     wholesale and hands the screen a Dart-constructed `User`. It therefore
//     cannot testify that `phoneNumber` and `professionalTitle` SURVIVE the
//     `UserProfileResponse` decode — a JSON-shape fact, not a Dart-value fact.
//     Both fields are rendered CONDITIONALLY here, so a decode that dropped
//     them would silently render the exact same "field not set" layout the
//     widget tests also accept as correct in their own no-phone/no-title cases.
//   • It also overrides `salonManagementProfileProvider(salonId)` wholesale.
//     That is the load-bearing REUSE decision of the whole phase (the screen
//     deliberately does NOT add a new single-endpoint provider — see its
//     header), and a provider-level override cannot tell a reachable endpoint
//     choice from a 403ing one. An admin calling `GET /salons/{id}` +
//     `GET /salons/{id}/staff` is exactly the pair `salonManageGuard` scopes to
//     owner+admin, and this file is what proves the admin really may call it.
//   • Neither tier reaches the locality cascade AT ALL: every widget fixture
//     hands the card a `Salon` with a blank `cityId`, which short-circuits
//     `resolvedLocalityProvider` before it requests anything. The address line
//     under the salon name is produced by three chained wire reads
//     (`/salons/{id}` -> `/locations/oblasts` -> `.../cities`) and is asserted
//     here for the first time.
//   • `salon_shell_screen_test.dart` proves the slot-2 admin swap against
//     stubbed providers and a synthetic shell entry — not against a real
//     post-login landing where the admin arrives via
//     `SalonHomeResolverScreen`'s synchronous `session.user.salonId` arm.
//   • The guard group in `admin_own_profile_screen_test.dart` drives the real
//     router but with every landing provider stubbed. The DEEP-LINK denial
//     below runs it against the real reads, which is the shape an external
//     link actually arrives in.
//
// NO PATROL FLOW IS WARRANTED (mobile-qa explicit statement). Step 2.7 Rule 3b
// requires an `integration_test/patrol/` flow only for a NATIVE interaction —
// an OS permission dialog, a deep link / app link handed over by the platform,
// FCM or a local notification, a WebView, or biometrics. Phase 21.16 has none:
// `AdminOwnProfileScreen` is pure Flutter chrome over three HTTP reads, the
// `/profile/admin` route is an INTERNAL go_router path that nothing external
// links to (`app_router.dart` calls it "the stand-alone entry only" and no
// `intent-filter`/`android:host` covers it), and the one platform channel the
// screen touches — `ScreenProtectionManager` — is already pinned at the widget
// tier by a real refcount, not by a native dialog. A patrol flow here would be
// a slower copy of this file with `$.native` unused: coverage theatre.
//
// THE ADMIN PERSONA'S CONTACTS (fixture note)
// -------------------------------------------
// `_adminUserJson` now carries `phoneNumber` + `professionalTitle` (added with
// this file — see its doc in `fake_backend.dart`). Before that it carried
// neither, so every assertion below about the «Контакти» section and the
// title sub-line would have been satisfied by the section simply being ABSENT
// — a fixture that cannot move the assertion, which is the trap M14 and the
// 21.14 F3 follow-up both name. `instagram` is still deliberately absent.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/presentation/client_contacts_edit_screen.dart';
import 'package:beautica_mobile/features/home/presentation/client_personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/admin_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_shell_tab_placeholder.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

/// `_adminUserJson.salonId` — the ONLY salon a SALON_ADMIN can ever resolve to
/// (`salonManageGuard`'s admin arm is an exact `User.salonId` match), and
/// deliberately a different id from the owner fixture's `salon-owner-1`.
const String _kAdminSalonId = 'salon-admin-1';

/// `SalonBottomNav.ownerAdminItems` — «Профіль» is destination 3…
const int _navProfile = 3;

/// …and «Салон» is destination 0, which is also the affiliation card's
/// destination.
const int _navSalon = 0;

/// The `IndexedStack` slot «Профіль» resolves to. A DIFFERENT number from
/// [_navProfile] on purpose — nav index and stack slot are not the same thing
/// here (nav 0 and nav 2 share slot 0), which is the conflation
/// `salon_shell_screen.dart`'s own NAV INDEX vs STACK SLOT note warns about.
const int _slotOwnProfile = 2;

/// The values the fixtures serve, asserted by VALUE rather than by mere tile
/// presence — a tile wired to the wrong `UserProfileResponse` key would still
/// be findable.
const String _kAdminPhone = '+380663334455';
const String _kAdminTitle = 'Старший адміністратор';
const String _kAdminSalonName = 'Салон Адміністратора';
const String _kAdminSalonCity = 'Київ';

Future<GoRouter> _enterShellAs(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
  String salonId,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);

  expect(
    find.byKey(const ValueKey<String>('login_email')),
    findsOneWidget,
    reason: 'cold start with no stored token must show the login form',
  );

  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);

  expect(
    AppHarness.location(router),
    equals(RouteNames.salonShell(salonId)),
    reason:
        'the journey under test starts from the REAL post-login landing, not '
        'a router.go() shortcut — if this is not the shell, the nav tap below '
        'is testing something else entirely.',
  );
  expect(find.byType(SalonShellScreen), findsOneWidget);
  return router;
}

Future<void> _tapNav(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(Key('salon-nav-tile-$index')));
  await AppHarness.settle(tester);
}

int? _stackIndex(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index;

/// Reads the string a keyed `Text` actually renders. Used instead of a
/// `find.descendant(...)`: these keys sit ON the `Text` itself, and a
/// descendant finder excludes its own root.
String? _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_ADMIN signs in -> salon shell -> «Профіль» renders the REAL admin '
    'own-profile screen (not the placeholder) with identity, salon and '
    'contacts all decoded off the wire',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
        await _enterShellAs(tester, fb, UserRole.salonAdmin, _kAdminSalonId);

        await _tapNav(tester, _navProfile);

        expect(
          _stackIndex(tester),
          _slotOwnProfile,
          reason: 'nav 3 must resolve to stack slot 2',
        );
        expect(
          find.byType(AdminOwnProfileScreen),
          findsOneWidget,
          reason:
              'THE PHASE 21.16 SWAP. Slot 2 rendered SalonShellTabPlaceholder '
              'for the admin until this phase; it must now be the real screen.',
        );
        expect(
          find.byType(SalonShellTabPlaceholder, skipOffstage: false),
          findsNothing,
          reason: 'the admin must never see the «скоро» placeholder here',
        );
        expect(
          find.byType(OwnerOwnProfileScreen, skipOffstage: false),
          findsNothing,
          reason:
              'and it must be the ADMIN screen, not the owner one — the two '
              'branches are two separate constructor calls on the same slot.',
        );
        expect(
          find.byType(ErrorState),
          findsNothing,
          reason:
              'both reads are reachable for a SALON_ADMIN — an ErrorState here '
              'means the screen picked an endpoint the admin\'s role cannot '
              'call.',
        );

        // ── Identity, from GET /users/me ──────────────────────────────────
        expect(
          _textOf(tester, 'admin-own-profile-name'),
          'Ірина Адміністратор',
          reason:
              'firstName + lastName really survived the UserProfileResponse '
              'decode and were joined — a Dart-constructed fixture cannot '
              'prove this.',
        );
        expect(
          find.byKey(const Key('admin-own-profile-role-chip')),
          findsOneWidget,
        );
        expect(
          _textOf(tester, 'admin-own-profile-professional-title'),
          _kAdminTitle,
          reason:
              'the self-declared title is a CONDITIONAL sub-line: if the key '
              'were dropped in the decode the screen would render the '
              'no-title layout, which is also a valid layout — so only the '
              'VALUE can tell the two apart.',
        );

        // ── «Салон», from GET /salons/salon-admin-1 + the locality cascade ─
        expect(
          find.byKey(const Key('admin-own-profile-salon')),
          findsOneWidget,
        );
        expect(
          _textOf(tester, 'salon-affiliation-card-name'),
          _kAdminSalonName,
          reason:
              'the affiliation card is fed by the REUSED '
              'salonManagementProfileProvider — this is what proves an admin '
              'may actually call GET /salons/{id} for their own salon.',
        );
        final AppLocalizations uk = await AppLocalizations.delegate.load(
          const Locale('uk'),
        );
        expect(
          _textOf(tester, 'salon-affiliation-card-locality'),
          '${uk.settlementCityPrefix} $_kAdminSalonCity',
          reason:
              'Phase 348 — the address line is the SHORT settlement label '
              '(«м. Київ», no oblast) composed from /salons/{id} '
              'citySettlementType (backend Phase 330). Every widget-tier '
              'fixture blanks cityId, so this is its ONLY end-to-end '
              'assertion.',
        );

        // ── «Контакти» — phone ONLY, and no Instagram tile ────────────────
        // The phone key sits on a `ContactTile`, not on a `Text`, so this one
        // reads through a descendant finder rather than [_textOf].
        expect(
          find.descendant(
            of: find.byKey(const Key('admin-own-profile-contact-phone')),
            matching: find.text(_kAdminPhone),
          ),
          findsOneWidget,
          reason: 'the decoded number, not an em-dash and not a stale default',
        );
        expect(
          find.byIcon(Icons.alternate_email),
          findsNothing,
          reason:
              'an Instagram handle is public marketing surface, not '
              'staff-internal data — the admin profile never draws that tile.',
        );

        // Sanity: the two reads really did cross the wire, so the assertions
        // above cannot be satisfied by a cache warmed on another surface.
        expect(fb.getSalonByIdCalls, greaterThan(0));
        expect(fb.lastGetSalonId, equals(_kAdminSalonId));
        expect(
          fb.getMasterCalls,
          equals(0),
          reason:
              'the admin branch must NOT reach the owner loader — a '
              'GET /masters/me from an admin session is the fingerprint of the '
              'wrong screen having been mounted on slot 2.',
        );
      });
    },
  );

  testWidgets(
    'tapping the affiliation card takes the admin back to «Салон» — the nav '
    'move, not a route push',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
        final GoRouter router = await _enterShellAs(
          tester,
          fb,
          UserRole.salonAdmin,
          _kAdminSalonId,
        );

        await _tapNav(tester, _navProfile);
        expect(find.byType(AdminOwnProfileScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('admin-own-profile-salon-card')));
        await AppHarness.settle(tester);

        expect(
          _stackIndex(tester),
          0,
          reason:
              'nav 0 «Салон» is stack slot 0 — the card moves the shell\'s own '
              'selection.',
        );
        expect(
          find.byKey(const Key('admin-own-profile-name')),
          findsNothing,
          reason:
              'what must not happen is the admin profile staying ON SCREEN. '
              'The screen WIDGET is deliberately still mounted — a raw '
              '`IndexedStack` never disposes a visited child, which is the '
              'whole reason `visible:` is threaded down — so the assertion is '
              'about what is PAINTED (the default finder skips the '
              'non-current child), never about the widget being gone.',
        );
        expect(
          AppHarness.location(router),
          equals(RouteNames.salonShell(_kAdminSalonId)),
          reason:
              'THE POINT: this is a nav selection INSIDE the shell, not a '
              'route push. A card wired to `context.push` would leave the '
              'admin one back-press from a screen the bottom nav does not '
              'own, and the location would have changed.',
        );
        expect(
          find.byKey(const Key('salon-nav-tile-$_navSalon')),
          findsOneWidget,
          reason: 'sanity: the bottom nav is still the shell\'s own',
        );
      });
    },
  );

  testWidgets(
    'a SALON_OWNER deep-linking /profile/admin is BOUNCED by the REAL guard, '
    'against the REAL reads',
    (tester) async {
      await mockNetworkImagesFor(() async {
        // The owner is the one role a naive "both salon roles" guard would let
        // through — `salonHomeGuard` admits it, which is exactly why
        // `/profile/admin` could not reuse that closure.
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.settle(tester);

        router.go(RouteNames.adminOwnProfile);
        await AppHarness.settle(tester);

        expect(
          find.byType(AdminOwnProfileScreen, skipOffstage: false),
          findsNothing,
          reason:
              'the resolved PAGE TYPE, not a location string: `/profile/admin` '
              'is a literal sibling of `/profile/owner`, and a future dynamic '
              '`/profile/:id` declared before either would absorb the path '
              'while the URI kept reporting `/profile/admin` verbatim.',
        );
        expect(
          find.byType(SalonShellScreen),
          findsOneWidget,
          reason:
              'roleHomePath sends a SALON_OWNER to the shared salon landing, '
              'which resolves to their own salon shell.',
        );
        expect(
          AppHarness.location(router),
          isNot(RouteNames.adminOwnProfile),
          reason: 'the guard must REDIRECT, not merely render something else',
        );
      });
    },
  );

  // DEBUG-chain fix (2026-09-26) — the user-reported bug: the tune button
  // used to push «Акаунт» directly, so an admin had NO sign-out affordance
  // anywhere on this path and «Видалити акаунт» read as the terminal action.
  // This proves the REAL fix end to end: tune -> the admin settings hub ->
  // «Вийти» -> confirm -> the REAL AuthNotifier.logout() round trip ->
  // /login, mirroring the coverage `logout_flow_test.dart` already has for
  // the other roles' hubs.
  testWidgets('SALON_ADMIN signs out from the settings hub: tune -> the admin '
      'settings hub -> «Вийти» -> confirm -> the REAL logout() fires and the '
      'admin lands on /login', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
      final GoRouter router = await _enterShellAs(
        tester,
        fb,
        UserRole.salonAdmin,
        _kAdminSalonId,
      );

      await _tapNav(tester, _navProfile);
      expect(find.byType(AdminOwnProfileScreen), findsOneWidget);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('btn-admin-own-profile-settings')),
      );
      await AppHarness.settle(tester);
      expect(
        AppHarness.location(router),
        equals(RouteNames.adminSettings),
        reason: 'the tune button must open the admin settings hub',
      );
      expect(find.byType(SettingsHubScreen), findsOneWidget);

      final int logoutCallsBefore = fb.logoutCalls;

      await AppHarness.tapVisible(tester, find.byKey(const Key('row-logout')));
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('btn-logout-confirm')),
        findsOneWidget,
        reason: 'the terminal row must raise the confirm dialog',
      );

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('btn-logout-confirm')),
      );
      // fixed-wait-ok: integration test, real async (logout + teardown +
      // redirect); bounded pumpAndSettle is the recommended real-async
      // settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        AppHarness.location(router),
        equals(RouteNames.login),
        reason: 'a successful sign-out must land the admin on /login',
      );
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      expect(
        fb.logoutCalls,
        equals(logoutCallsBefore + 1),
        reason: 'confirming must invoke the REAL logout() exactly once',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Phase 356 — the admin hub's «Особисті дані» / «Контакти» rows are no
  // longer «незабаром»: they reuse the CLIENT editor screens and PATCH the
  // REAL `/users/me` endpoint. Proves the round trip end to end, including
  // the two surfaces D6 names: the own-profile card (already covered by the
  // pre-existing `clientEditProfileProvider` invalidation) and the salon
  // «Команда» roster (the NEW `salonManagementProfileProvider` invalidation
  // this phase adds — see `client_edit_profile_notifier.dart`'s
  // `invalidateOwnIdentity` doc).
  // ---------------------------------------------------------------------
  testWidgets(
    'SALON_ADMIN edits «Особисті дані» from the settings hub: the new name '
    'reflects on the own-profile card AND on salon «Команда» without a '
    'restart',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
        final GoRouter router = await _enterShellAs(
          tester,
          fb,
          UserRole.salonAdmin,
          _kAdminSalonId,
        );

        await _tapNav(tester, _navProfile);
        expect(find.byType(AdminOwnProfileScreen), findsOneWidget);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-admin-own-profile-settings')),
        );
        await AppHarness.settle(tester);
        expect(find.byType(SettingsHubScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('row-personal')));
        await AppHarness.settle(tester);
        expect(
          AppHarness.location(router),
          equals(RouteNames.adminEditPersonal),
          reason: 'Phase 356 — «Особисті дані» must be a LIVE row now',
        );
        expect(find.byType(ClientPersonalInfoEditScreen), findsOneWidget);

        final Finder firstNameField = find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        );
        final Finder lastNameField = find.descendant(
          of: find.byKey(const Key('field-lastName')),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(firstNameField).controller?.text,
          'Ірина',
          reason: 'the field must pre-populate from the REAL /users/me read',
        );

        await tester.tap(firstNameField);
        await AppHarness.settle(tester);
        await tester.enterText(firstNameField, 'Оксана');
        await tester.pump();
        await tester.tap(lastNameField);
        await AppHarness.settle(tester);
        await tester.enterText(lastNameField, 'Керівник');
        await tester.pump();

        final int patchesBefore = fb.patchMeCalls;

        await tester.tap(find.byKey(const Key('btn-save-personal')));
        await AppHarness.settle(tester);

        expect(
          fb.patchMeCalls,
          equals(patchesBefore + 1),
          reason: 'Save must issue exactly one PATCH /users/me',
        );
        expect(
          fb.adminFirstName,
          'Оксана',
          reason: 'the PATCH must persist onto the mutable admin identity',
        );
        expect(fb.adminLastName, 'Керівник');

        // `doneRoute: RouteNames.adminSettings` is `context.go`, which
        // REPLACES the whole nav stack — the shell this journey started
        // from is gone from history, so the save lands on the admin hub,
        // not on a popped profile screen.
        expect(
          AppHarness.location(router),
          equals(RouteNames.adminSettings),
          reason: 'doneRoute must route the save back to the admin hub',
        );
        expect(find.byType(SettingsHubScreen), findsOneWidget);

        // Drain the "saved" VelvetSnack's dwell Timer. It is a ROOT-overlay
        // entry (never a descendant of the routed screen — see
        // `velvet_snack_matchers.dart`'s header), so it survives the
        // `context.go` above and, left undrained, still bottom-anchors over
        // whatever mounts next — including the shell's bottom nav this test
        // re-enters further down, which is exactly what it silently blocked
        // before this call was added.
        await pumpPastVelvetSnack(tester);

        // Close the hub — with no history left (go() discarded it above),
        // this resolves to the fallbackHomeRoute: the STAND-ALONE admin
        // profile ([RouteNames.adminOwnProfile]).
        await tester.tap(find.byKey(const Key('btn-close-hub')));
        await AppHarness.settle(tester);

        expect(AppHarness.location(router), equals(RouteNames.adminOwnProfile));
        expect(
          _textOf(tester, 'admin-own-profile-name'),
          'Оксана Керівник',
          reason:
              'the own-profile card must show the NEW name without a '
              'restart — clientEditProfileProvider was invalidated on save '
              '(this half was already covered before this phase; see D6)',
        );

        // Re-enter the shell — discarded from history by the `go()` above,
        // exactly like every pre-existing `doneRoute: null` CLIENT save —
        // and open «Команда»: the admin's own roster row must show the new
        // firstName too. THIS is the NEW half of D6: before this phase's
        // `invalidateOwnIdentity` fix, `salonManagementProfileProvider`
        // stayed warm with the pre-save name.
        router.go(RouteNames.salonShell(_kAdminSalonId));
        await AppHarness.settle(tester);
        await _tapNav(tester, kSalonTeamNavTab);

        final Finder ownCard = find.byKey(
          const Key('salon-manage-staff-card-user-admin-1'),
        );
        await AppHarness.revealRosterCard(tester, ownCard);
        expect(
          // i18n-finder-ok: a person's own firstName is locale-invariant
          // fixture DATA (`fb.adminFirstName`), not localized UI copy.
          find.descendant(of: ownCard, matching: find.text('Оксана')),
          findsOneWidget,
          reason:
              '«Команда» is UNFILTERED and renders the viewer\'s own row — '
              'it must reflect the new name, not the pre-save one',
        );
      });
    },
  );

  testWidgets(
    'SALON_ADMIN edits «Контакти» from the settings hub: the new phone '
    'reflects on the own-profile contact tile without a restart',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
        final GoRouter router = await _enterShellAs(
          tester,
          fb,
          UserRole.salonAdmin,
          _kAdminSalonId,
        );

        await _tapNav(tester, _navProfile);
        expect(find.byType(AdminOwnProfileScreen), findsOneWidget);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-admin-own-profile-settings')),
        );
        await AppHarness.settle(tester);

        await tester.tap(find.byKey(const Key('row-contacts')));
        await AppHarness.settle(tester);
        expect(
          AppHarness.location(router),
          equals(RouteNames.adminEditContacts),
          reason: 'Phase 356 — «Контакти» must be a LIVE row now',
        );
        expect(find.byType(ClientContactsEditScreen), findsOneWidget);
        expect(
          find.byKey(const Key('field-instagram')),
          findsNothing,
          reason:
              'the admin profile deliberately has no Instagram tile — the '
              'reused screen must stay phone-only for this caller too',
        );

        final Finder phoneField = find.descendant(
          of: find.byKey(const Key('field-phone')),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(phoneField).controller?.text,
          _kAdminPhone,
          reason: 'the field must pre-populate from the REAL /users/me read',
        );

        final int patchesBefore = fb.patchMeCalls;

        await tester.enterText(phoneField, '+380 67 111 22 33');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('btn-save-contacts')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-save-contacts')));
        await AppHarness.settle(tester);

        expect(fb.patchMeCalls, equals(patchesBefore + 1));
        expect(
          fb.adminPhone,
          contains('67 111 22 33'),
          reason: 'the PATCH must persist onto the mutable admin identity',
        );
        expect(
          fb.lastPatchMeBody?.containsKey('instagram'),
          isFalse,
          reason: 'ClientContactsEditScreen must NEVER send instagram',
        );

        expect(
          AppHarness.location(router),
          equals(RouteNames.adminSettings),
          reason: 'doneRoute must route the save back to the admin hub',
        );

        // Drain the "saved" VelvetSnack — see the identical comment on the
        // personal-info test above.
        await pumpPastVelvetSnack(tester);

        // Same history-discard mechanics as the personal-info test above.
        await tester.tap(find.byKey(const Key('btn-close-hub')));
        await AppHarness.settle(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('admin-own-profile-contact-phone')),
            matching: find.text('+380 67 111 22 33'),
          ),
          findsOneWidget,
          reason:
              'the own-profile phone tile must show the NEW number without '
              'a restart',
        );
      });
    },
  );
}
