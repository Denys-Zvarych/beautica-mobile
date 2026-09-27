// mobile-qa (2026-09-01) — E2E: the SALON_OWNER's own «Профіль» tab
// (Phase 21.14), end to end, through the REAL router, the REAL
// `mySalonsGuard`/`salonManageGuard` admission and the REAL
// `GET /users/me` + `GET /masters/me` + `GET /masters/{id}/services` reads.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// Phase 21.14 swapped a placeholder for a real screen on a surface the user
// reaches by tapping a bottom-nav destination after signing in. That is a
// screen + route + provider↔repository wiring change, so a widget test alone
// is not sufficient coverage. What the widget tests CANNOT reach:
//
//   • `owner_own_profile_screen_test.dart` overrides `ownerOwnProfileProvider`
//     wholesale — so it never runs the loader at all, and cannot observe that
//     the three endpoints are reachable for a SALON_OWNER. That matters
//     concretely here: the loader deliberately does NOT use
//     `servicesListProvider` (`GET /independent-masters/me/services` is
//     `INDEPENDENT_MASTER`-only and 403s for an owner) and instead reads the
//     PUBLIC `GET /masters/{masterRowId}/services`, keyed on the master-ROW id
//     that only `GET /masters/me` supplies. A provider-level override cannot
//     tell a correct endpoint choice from a wrong one.
//   • `owner_own_profile_notifier_test.dart` stubs both upstream NOTIFIERS, so
//     it never crosses the wire either — `hasMasterProfile` is handed to it as
//     a Dart field, not decoded from a `UserProfileResponse` whose key may
//     simply be ABSENT (the `null` arm of the tri-state is a JSON-shape fact,
//     not a Dart-value fact).
//   • `salon_shell_screen_test.dart` proves the slot-2 swap against stubbed
//     providers and a synthetic shell entry — not against a real post-login
//     landing where the owner arrives via `SalonHomeResolverScreen`.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView, or biometric — this is a pure screen/nav/provider
// surface, so Step 2.7 Rule 3b's `integration_test/patrol/` requirement does
// not apply (mobile-qa explicit statement).
//
// THE TRI-STATE, ACROSS THE WIRE
// ------------------------------
// `UserProfileResponse.hasMasterProfile` is `bool?` and its three states are
// NOT two (`owner_own_profile_notifier.dart`'s own header states the contract):
//
//   ABSENT KEY  → unknown → probe `GET /masters/me` → 200 → section PRESENT
//   `true`      → probe → 200 → section PRESENT
//   `false`     → proven negative → section ABSENT, catalogue never read
//   ABSENT/true + `/masters/me` 404 → section degrades to ABSENT, and the tab
//                 must still RENDER (never an ErrorState) — only the
//                 `/users/me` read may error this screen.
//
// The 404 case is the one worth spelling out: it is both the steady state for
// an owner who does not perform services and the RACE where the master row was
// deactivated between the two reads. Both must look the same to the user.
//
// FakeBackend knobs used: `hasMasterProfile` (mutable, read per `/users/me`
// request) and `masterMeNotFound` (constructor-time — `DioAdapter.onRoute`
// fixes a route's status code at registration). See their docs.
//
// NOTE on `AppHarness.loginAs`: it now has a `salonAdmin` arm submitting
// `admin@beautica.ua` (mobile-qa 21.14 F2 — it used to fall through to the
// master persona's email). Nothing here depends on that either way:
// FakeBackend branches on `currentRole`, not on the submitted email, so the
// admin case below asserts on the RESOLVED role's rendered slot, never on the
// login credentials.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_shell_tab_placeholder.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// [FakeBackend.mySalons]'s default single-primary salon — where a
/// `SALON_OWNER` lands straight after login.
const String _kOwnerSalonId = 'salon-owner-1';

/// `SalonBottomNav.ownerAdminItems` — «Профіль» is destination 3.
const int _navProfile = 3;

/// …and it renders `IndexedStack` SLOT 2. Deliberately a separate constant
/// from [_navProfile]: nav index and stack slot are different numbers here
/// (nav 0 and nav 2 share slot 0), and conflating them is the exact mistake
/// `salon_shell_screen.dart`'s own NAV INDEX vs STACK SLOT note warns about.
const int _slotOwnProfile = 2;

Finder get _profileTab =>
    find.byKey(const Key('salon-shell-tab-profile-owner'));

/// Boots the app, signs [role] in, and asserts the salon shell is what the
/// post-login landing actually resolved to.
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
        'a router.go() shortcut — if this is not the shell the tab tap below '
        'is testing something else entirely.',
  );
  expect(find.byType(SalonShellScreen), findsOneWidget);
  return router;
}

/// Taps a bottom-nav destination and settles.
Future<void> _tapNav(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(Key('salon-nav-tile-$index')));
  await AppHarness.settle(tester);
}

/// The `IndexedStack` slot actually on screen.
int? _stackIndex(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER signs in -> salon shell -> «Профіль» renders the REAL '
    'own-profile screen (not the placeholder), with the master section '
    'PRESENT when hasMasterProfile is true',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..hasMasterProfile = true;
        await _enterShellAs(tester, fb, UserRole.salonOwner, _kOwnerSalonId);

        await _tapNav(tester, _navProfile);

        expect(
          _stackIndex(tester),
          _slotOwnProfile,
          reason: 'nav 3 must resolve to stack slot 2',
        );
        expect(
          find.byType(OwnerOwnProfileScreen),
          findsOneWidget,
          reason:
              'THE PHASE 21.14 SWAP. Slot 2 used to render '
              'SalonShellTabPlaceholder for both roles; the owner branch must '
              'now be the real screen.',
        );
        expect(
          find.descendant(
            of: _profileTab,
            matching: find.byType(SalonShellTabPlaceholder),
          ),
          findsNothing,
          reason: 'the owner must never see the «скоро» placeholder here',
        );
        expect(
          find.byType(ErrorState),
          findsNothing,
          reason:
              'all three reads are reachable for a SALON_OWNER — an ErrorState '
              'here means the loader picked an endpoint the owner\'s role '
              'cannot call.',
        );

        // Identity + contacts, from GET /users/me.
        expect(find.byKey(const Key('owner-own-profile-name')), findsOneWidget);
        expect(
          find.byKey(const Key('owner-own-profile-role-chip')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('owner-own-profile-contact-phone')),
          findsOneWidget,
          reason: 'the phone tile renders unconditionally (em-dash when unset)',
        );
        // POPULATED contacts (mobile-qa 21.14 F3). The owner persona now
        // carries both keys, so this crosses the wire for the arm the widget
        // tests cannot reach: they build a Dart `User` directly and therefore
        // cannot prove `phoneNumber`/`instagram` survive the
        // `UserProfileResponse` decode. Asserting the VALUES, not just the
        // keys — a tile wired to the wrong field would still be findable.
        expect(
          find.descendant(
            of: find.byKey(const Key('owner-own-profile-contact-phone')),
            matching: find.text('+380502222222'),
          ),
          findsOneWidget,
          reason: 'the phone tile shows the decoded number, not the em-dash',
        );
        // The Instagram tile is CONDITIONAL on a non-empty handle, so its mere
        // presence is the decode proof; the text assertion pins the value.
        expect(
          find.descendant(
            of: find.byKey(const Key('owner-own-profile-contact-instagram')),
            matching: find.text('@oksana_salon'),
          ),
          findsOneWidget,
          reason:
              'an owner with an Instagram handle must get the second contact '
              'tile — previously only the unset (tile-absent) path was covered '
              'end to end.',
        );

        // The owner-as-master section, from GET /masters/me +
        // GET /masters/{masterRowId}/services.
        expect(
          find.byKey(const Key('owner-own-profile-stats')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('owner-own-profile-bio')), findsOneWidget);
        expect(
          find.byKey(const Key('owner-own-profile-categories')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('owner-profile-category-NAILS')),
          findsOneWidget,
          reason:
              'the catalogue really was read through the PUBLIC '
              'GET /masters/{masterRowId}/services — the only services '
              'endpoint a SALON_OWNER may call. (An empty list would make '
              'ServiceCategoryCardList short-circuit to SizedBox.shrink(), so '
              'this assertion is also what proves the fixture is populated.)',
        );

        expect(
          fb.getMasterCalls,
          greaterThan(0),
          reason: 'sanity: GET /masters/me was genuinely reached over the wire',
        );
        expect(
          fb.getPublicMasterServicesCalls,
          greaterThan(0),
          reason:
              'sanity: the catalogue read really happened — otherwise the '
              'category assertion above could be satisfied by a stale cache '
              'from another surface.',
        );
        expect(
          fb.lastGetPublicMasterServicesId,
          equals(fb.masterRowId),
          reason:
              'the catalogue is keyed on the MASTER-ROW id from '
              'GET /masters/me, never on session.user.id.',
        );
      });
    },
  );

  testWidgets(
    'hasMasterProfile == false -> the master section is ABSENT and the '
    'catalogue is never read, but the tab still renders identity + contacts',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..hasMasterProfile = false;
        await _enterShellAs(tester, fb, UserRole.salonOwner, _kOwnerSalonId);

        await _tapNav(tester, _navProfile);

        expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
        expect(find.byType(ErrorState), findsNothing);
        expect(find.byKey(const Key('owner-own-profile-name')), findsOneWidget);
        expect(
          find.byKey(const Key('owner-own-profile-contact-phone')),
          findsOneWidget,
        );

        expect(find.byKey(const Key('owner-own-profile-stats')), findsNothing);
        expect(find.byKey(const Key('owner-own-profile-bio')), findsNothing);
        expect(
          find.byKey(const Key('owner-own-profile-categories')),
          findsNothing,
        );
        expect(
          fb.getPublicMasterServicesCalls,
          equals(0),
          reason:
              'a PROVEN negative must short-circuit before the catalogue read. '
              'The `/masters/me` probe is speculative (started in parallel '
              'before the gate value is known) and its RESULT is discarded — '
              'but the request keyed on it must never be issued.',
        );
      });
    },
  );

  testWidgets(
    'the key is ABSENT from GET /users/me (older backend) -> the loader falls '
    'through to the GET /masters/me probe and the section is PRESENT',
    (tester) async {
      await mockNetworkImagesFor(() async {
        // `hasMasterProfile` left unset — FakeBackend then OMITS the key
        // entirely, which is the wire shape, not a serialized null. This is
        // the arm a Dart-level fixture cannot express.
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        await _enterShellAs(tester, fb, UserRole.salonOwner, _kOwnerSalonId);

        await _tapNav(tester, _navProfile);

        expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
        expect(
          find.byKey(const Key('owner-own-profile-stats')),
          findsOneWidget,
          reason:
              'null is UNKNOWN, not a proven "no". The backend auto-creates '
              'the owner\'s master row on first-salon registration, so '
              'treating an absent key as false would blank the section for the '
              'COMMON case.',
        );
        expect(
          find.byKey(const Key('owner-own-profile-categories')),
          findsOneWidget,
        );
      });
    },
  );

  testWidgets(
    'GET /masters/me answers 404 -> the section degrades to ABSENT and the '
    'tab still renders; it is NOT an error state',
    (tester) async {
      await mockNetworkImagesFor(() async {
        // The steady state for an owner with no active master row, AND the
        // shape of the race the loader is written to tolerate: the flag said
        // true and the row was deactivated before `/masters/me` was reached.
        final fb = FakeBackend(masterMeNotFound: true)
          ..currentRole = UserRole.salonOwner
          ..hasMasterProfile = true;
        await _enterShellAs(tester, fb, UserRole.salonOwner, _kOwnerSalonId);

        await _tapNav(tester, _navProfile);

        expect(
          tester.takeException(),
          isNull,
          reason: 'a 404 on an OPTIONAL section must never surface as a crash',
        );
        expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
        expect(
          find.byType(ErrorState),
          findsNothing,
          reason:
              'ONLY the /users/me read may error this screen. Erroring an '
              'entire profile because an optional section 404\'d is a strictly '
              'worse failure than omitting the section.',
        );
        expect(
          find.byKey(const Key('owner-own-profile-name')),
          findsOneWidget,
          reason: 'the identity the screen exists to show is still rendered',
        );
        expect(find.byKey(const Key('owner-own-profile-stats')), findsNothing);
        expect(
          find.byKey(const Key('owner-own-profile-categories')),
          findsNothing,
        );
        expect(
          fb.getPublicMasterServicesCalls,
          equals(0),
          reason:
              'the catalogue endpoint is keyed on Master.id, which the failed '
              'probe never supplied — it must not be called with a guess.',
        );
      });
    },
  );

  testWidgets(
    'the ADMIN branch stays SEPARATE: SALON_ADMIN\'s «Профіль» is the admin '
    'screen (Phase 21.16), never the owner one',
    (tester) async {
      await mockNetworkImagesFor(() async {
        // mobile-qa (2026-09-05) — RENAMED at Phase 21.16. This test used to
        // say the admin branch was "still the placeholder"; that phase
        // replaced the placeholder with `AdminOwnProfileScreen`, and every
        // assertion in the body was written loosely enough (key present,
        // OwnerOwnProfileScreen absent, no /masters/me) to stay green through
        // the swap — so the NAME went stale while the file stayed passing. The
        // positive half of the swap is asserted end to end in
        // `admin_own_profile_flow_test.dart`; what stays here is the
        // owner-flow-scoped claim it always made.
        //
        // Guards the swap in the OTHER direction. Without this a change that
        // hosted the owner screen for both roles would leave every assertion
        // above green while shipping an owner-shaped profile — reading
        // `GET /masters/me` and the owner's own catalogue — to an admin.
        //
        // `_adminUserJson.salonId` is 'salon-admin-1', deliberately distinct
        // from the owner fixture's primary salon.
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
        await _enterShellAs(tester, fb, UserRole.salonAdmin, 'salon-admin-1');

        await _tapNav(tester, _navProfile);

        expect(
          _stackIndex(tester),
          _slotOwnProfile,
          reason: 'sanity: the admin really is on the «Профіль» slot',
        );
        expect(
          find.byKey(const Key('salon-shell-tab-profile-admin')),
          findsOneWidget,
        );
        expect(find.byType(OwnerOwnProfileScreen), findsNothing);
        expect(
          fb.getMasterCalls,
          equals(0),
          reason:
              'the admin branch must not reach the owner loader at all — a '
              'GET /masters/me from an admin session is the fingerprint of '
              'the wrong screen having been mounted.',
        );
      });
    },
  );
}
