// mobile-qa (2026-08-30) — E2E: the Salon Shell's bottom nav and the salon
// management profile's in-screen tab row are ONE selection, in BOTH directions.
//
// THE BUG
// -------
// Tapping the in-screen «Команда» tab swapped the body to the staff grid but
// left the bottom-nav highlight on the previous destination. All four in-screen
// tabs were disconnected from the nav; «Команда» was simply the only one with a
// nav counterpart, so it was the only one where the desync was visible. The
// in-screen index used to be private `setState` state inside
// `SalonManagementProfileScreen`, seeded once by a one-way `initialTab` and
// unable to report a later tap back to the shell.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// `test/features/salon/presentation/salon_shell_screen_test.dart` proves the
// same sync against a STUBBED `salonManagementProfileProvider`, and its
// round-trip case asserts the reconciled index by READING
// `SalonManagementProfileScreen.tab` off the widget — a constructor-argument
// read, not a render. That cannot catch:
//   • the reconciliation surviving a REAL router entry into `/shell` with a
//     REAL `salonManageGuard` admission and REAL `GET /salons/{id}` +
//     `GET /salons/{id}/staff` loads behind both hosted instances;
//   • what the «Салон» destination ACTUALLY RENDERS after a round trip.
//     `IndexedStack` never disposes a visited child, so slot 0 stays mounted
//     with a live `State` the whole time; the failure mode this pins is the
//     «Салон» destination coming back showing the STAFF GRID. A `.tab` field
//     read cannot observe that — only an assertion on the rendered body can.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView, or biometric — this is a pure screen/nav/provider
// surface, so Step 2.7 Rule 3b's `integration_test/patrol/` requirement does
// not apply (mobile-qa explicit statement).
//
// NAV INDEX vs STACK SLOT (mobile-perf LOW follow-up, 2026-08-30)
// ----------------------------------------------------------------
// «Салон» (nav 0) and «Команда» (nav 2) used to be TWO byte-identical
// `SalonManagementProfileScreen` children of the shell's `IndexedStack`,
// differing only by `Key` — so one of them was always offstage rendering a
// duplicate of what the user was looking at (and, via
// `_SalonReviewsSectionState._sort`, keeping a second
// `salonReviewsProvider(salonId, <stale sort>)` family instance alive). They
// now share ONE host at stack slot 0; the stack has 3 children while the nav
// keeps 4 destinations:
//
//   nav 0 «Салон» ─┬─> stack slot 0 (the one profile host)
//   nav 2 «Команда»┘
//   nav 1 «Записи» ──> stack slot 1
//   nav 3 «Профіль»──> stack slot 2
//
// The BEHAVIOURAL assertions in this file are unchanged by that — nav
// highlight, rendered tab body, the real staff card, and the no-bleed
// guarantee all still say exactly what they said. What changed is the
// STRUCTURAL pins that encoded the two-slot shape: `IndexedStack.index` is no
// longer equal to the nav index for «Команда», and there is no offstage twin
// left to assert the presence of. Those are restated below against the new
// mapping (and strengthened with an explicit "exactly one host exists"
// assertion, which is the dedupe itself).
//
// OFFSTAGE TRAP (the one that has already cost a false failure on this exact
// screen — recorded in `docs/mobile-phases/mobile-backlog.md`): `IndexedStack`
// keeps every non-current child MOUNTED but OFFSTAGE, and `find.byKey` /
// `find.byType` default to `skipOffstage: true`. So:
//   • a DEFAULT finder answers "what is on screen right now" — which is
//     exactly what every render assertion below wants, because both hosted
//     instances render the same keys;
//   • `skipOffstage: false` is used ONLY where the point is "this child is
//     still mounted behind the current one".
// Before the dedupe both instances emitted the SAME `salon-tab-N` /
// `salon-manage-tab-body-*` keys, so a `skipOffstage: false` render assertion
// was ambiguous by construction, not merely noisy. Only one host survives
// now, but the default-true convention stays: these assertions are about what
// is ON SCREEN, and a lazily-unbuilt sibling slot can still make an offstage
// finder answer a different question than the one being asked.
//
// Fixture: `salon-xyz` — the salon whose detail + staff roster `FakeBackend`
// already serves in full (the shell's own default `salon-owner-1` has a
// `GET /salons/mine` row but no salon-detail fixture, so its «Салон» slot
// renders an error state and no tab body at all).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kSalonId = 'salon-xyz';

/// Bottom-nav destinations (`SalonBottomNav.ownerAdminItems`).
const int _navSalon = 0;
const int _navTeam = 2;

/// The `IndexedStack` SLOT that BOTH [_navSalon] and [_navTeam] render — see
/// the NAV INDEX vs STACK SLOT note in the header. This is deliberately a
/// separate constant from the nav indices above: writing `_navTeam` where a
/// stack slot is meant is the exact conflation the dedupe made possible.
const int _slotProfile = 0;

/// In-screen sub-tabs of `SalonManagementProfileScreen`.
const int _subAbout = 0;
const int _subStaff = 1;

/// See `salon_management_profile_flow_test.dart`'s copy of this helper —
/// `salonManageGuard`'s SALON_OWNER arm authorizes the route's `:salonId`
/// against the REAL `mySalonsProvider` list, which by default holds only
/// `salon-owner-1`. `isPrimary: false` keeps `salon-owner-1` the primary so
/// the post-login landing is unaffected.
void _seedSalonXyzIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonId,
    'ownerId': 'user-owner-1',
    'name': 'Студія Краси «Камелія»',
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'isActive': true,
    'isPrimary': false,
  });
}

/// The shell's current bottom-nav highlight — the thing the reported bug left
/// stale.
int _navIndex(WidgetTester tester) => tester
    .widget<SalonBottomNav>(find.byKey(const Key('salon-shell-bottom-nav')))
    .currentIndex;

/// The `IndexedStack` slot actually on screen. `IndexedStack.index` is
/// nullable (a null index paints nothing at all); the shell always passes a
/// concrete tab, so a null here is itself a failure worth surfacing.
int? _stackIndex(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index;

/// ON-SCREEN body of whichever hosted profile screen is current — see the
/// OFFSTAGE TRAP note in the file header for why this stays `skipOffstage`
/// default-true.
Finder _visibleTabBody(String tabKey) =>
    find.byKey(ValueKey<String>('salon-manage-tab-body-$tabKey'));

/// Boots the app, logs a SALON_OWNER in, and enters the shell for [_kSalonId].
Future<GoRouter> _enterShell(WidgetTester tester, FakeBackend fb) async {
  _seedSalonXyzIntoMySalons(fb);
  final GoRouter router = await AppHarness.boot(tester, fb);

  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  await AppHarness.settle(tester);

  router.go(RouteNames.salonShell(_kSalonId));
  await AppHarness.settle(tester);

  expect(
    find.byType(SalonShellScreen),
    findsOneWidget,
    reason: 'salonManageGuard must ADMIT a real SALON_OWNER on /shell',
  );
  return router;
}

/// Taps the in-screen sub-tab at [index] of the CURRENTLY VISIBLE profile
/// screen, scrolling it into view first — the tab row sits below the cover +
/// hero card and can start off-screen.
Future<void> _tapSubTab(WidgetTester tester, int index) async {
  final Finder tab = find.byKey(Key('salon-tab-$index'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  // A tab tap writes a provider that both hosted instances watch and can move
  // the IndexedStack slot — settle, never a bounded pump.
  await tester.pumpAndSettle();
}

Future<void> _tapNav(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(Key('salon-nav-tile-$index')));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('PART C — tapping the IN-SCREEN «Команда» tab from the «Салон» '
      'destination moves the bottom-nav highlight to «Команда» and swaps the '
      'shared host to the staff body', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      await _enterShell(tester, fb);

      expect(_navIndex(tester), _navSalon);
      expect(_stackIndex(tester), _slotProfile);
      expect(
        _visibleTabBody('about'),
        findsOneWidget,
        reason: 'the shell opens on «Салон» -> «Про салон»',
      );

      await _tapSubTab(tester, _subStaff);

      expect(
        _navIndex(tester),
        _navTeam,
        reason:
            'THE REPORTED BUG: the nav highlight used to stay on the '
            'previous destination while the body swapped underneath it',
      );
      expect(
        _stackIndex(tester),
        _slotProfile,
        reason:
            'the STACK does not move: «Команда» renders the same slot as '
            '«Салон». Asserting `_navTeam` here would be reading a nav index '
            'off `IndexedStack.index`.',
      );
      expect(
        find.byKey(const Key('salon-shell-slot-profile')),
        findsOneWidget,
        reason: 'the shared profile host must be the ON-SCREEN child',
      );
      expect(
        _visibleTabBody('staff'),
        findsOneWidget,
        reason: 'and it must actually render the staff grid',
      );
      // The real roster, from the real GET /salons/{id}/staff behind the
      // slot that just became visible — not merely an empty staff body.
      expect(
        find.byKey(const Key('salon-manage-staff-card-master-aaa')),
        findsOneWidget,
      );

      // THE DEDUPE (mobile-perf FINDING 1). This assertion replaces the pair
      // that used to prove the «Салон» twin was "still mounted offstage" —
      // that twin is exactly what was removed. `skipOffstage: false` is what
      // makes this real: the old shape hid its duplicate OFFSTAGE, so a
      // default finder would have reported `findsOneWidget` for the
      // two-instance tree too.
      expect(
        find.byType(SalonManagementProfileScreen, skipOffstage: false),
        findsOneWidget,
        reason:
            'exactly ONE profile host may exist in the whole tree — a second, '
            'offstage instance is a full duplicate render (cover, hero, tab '
            'body, controllers) of what the user is already looking at, plus '
            'a second _SalonReviewsSectionState pinning its own '
            'salonReviewsProvider(salonId, sort) family instance',
      );
    });
  });

  testWidgets('PART C, mirror — tapping the IN-SCREEN «Про салон» tab from the '
      '«Команда» destination moves the bottom-nav highlight back to «Салон»', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      await _enterShell(tester, fb);

      // Arrive at «Команда» via the NAV (the other direction of the sync):
      // selecting the destination must itself drive the sub-tab to the
      // staff grid, or this slot would render whatever an earlier in-screen
      // tap had parked the shared index on.
      await _tapNav(tester, _navTeam);
      expect(_navIndex(tester), _navTeam);
      expect(
        _visibleTabBody('staff'),
        findsOneWidget,
        reason:
            'nav -> sub-tab is the second direction of the reconciliation; '
            'without it the «Команда» destination shows «Про салон»',
      );

      await _tapSubTab(tester, _subAbout);

      expect(
        _navIndex(tester),
        _navSalon,
        reason:
            'the mirror case: an in-screen non-staff tab is the «Салон» '
            'destination, so the nav must follow it back',
      );
      expect(_stackIndex(tester), _slotProfile);
      expect(_visibleTabBody('about'), findsOneWidget);
    });
  });

  testWidgets(
    'PART C — a round trip through «Команда» leaves the «Салон» destination '
    'rendering its OWN «Про салон» body, not the staff grid it was left on',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        await _enterShell(tester, fb);

        await _tapSubTab(tester, _subStaff);
        expect(_navIndex(tester), _navTeam);
        expect(_visibleTabBody('staff'), findsOneWidget);

        await _tapNav(tester, _navSalon);

        expect(_navIndex(tester), _navSalon);
        expect(_stackIndex(tester), _slotProfile);
        expect(
          find.byKey(const Key('salon-shell-slot-profile')),
          findsOneWidget,
          reason: 'the shared profile host is the on-screen child again',
        );
        // THE ASSERTION THIS TEST EXISTS FOR — rendered body, not a `.tab`
        // constructor-argument read. Slot 0 was never disposed and its
        // `State` object is the same one that was live when the sub-tab moved
        // to «Команда»; an uncontrolled host would come back on the staff
        // grid.
        expect(
          _visibleTabBody('about'),
          findsOneWidget,
          reason:
              'the «Салон» destination must render «Про салон», not the '
              'sub-tab a visit to «Команда» left behind',
        );
        expect(_visibleTabBody('staff'), findsNothing);
        expect(
          find.byKey(const Key('salon-manage-staff-card-master-aaa')),
          findsNothing,
          reason: 'no staff grid may bleed across destinations',
        );
        // And the «Салон» body is the REAL loaded About tab (the salon's own
        // description from GET /salons/{id}), not an empty/error placeholder
        // that would satisfy "staff grid absent" for the wrong reason.
        expect(
          find.byKey(const Key('salon-manage-about-text')),
          findsOneWidget,
        );
      });
    },
  );
}
