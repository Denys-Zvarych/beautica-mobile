// M509 — E2E: the «Клієнти» tab on every provider surface (CLI-46 / CLI-47).
//
// REAL router (authRedirect + role gates), REAL `HttpClientRepository` and
// generated row models over a stubbed Dio (`FakeBackend.wireClientList`); only
// the transport is faked, so the wire contract — FLAT `page`/`size`, `q` only
// when valid, `masterId` only in owner master mode — is what is asserted.
//
//   (a) SALON_OWNER → salon shell → «Клієнти» → list → search → page 2 on
//       scroll → row tap opens the card route → back keeps the tab;
//   (b) INDEPENDENT_MASTER → master bar «Клієнти» → `/masters/me/clients`;
//   (c) SALON_MASTER → `/staff/clients` → `/masters/me/clients`, NEVER the
//       salon endpoint;
//   (d) owner master mode → `/owner/master/clients` → the SALON endpoint with
//       `masterId` = the owner's own master row.
//
// Search: `q` is sent only for a trimmed 2–50-char term; the 300 ms debounce
// is a `Timer`, driven with an explicit `pump(kClientSearchDebounce)`
// (`pumpAndSettle` fires no Timer). 800×600 surface: the list is scrolled
// before the next row is asserted.
//
// NO PATROL FLOW: nothing here touches an OS permission dialog, deep link,
// notification, WebView or biometric (mobile-qa explicit statement).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_placeholder_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart';

/// The owner's default landing salon (`FakeBackend.mySalons`).
const String _kSalonId = 'salon-owner-1';

/// Owner master mode: the owner's own `masters` ROW id (≠ the session user
/// id, so a request built off the wrong id cannot match).
const String _kOwnerMasterRowId = 'master-row-owner-1';

const String _kMasterPath = '/api/v1/masters/me/clients';
const String _kSalonPath = '/api/v1/salons/$_kSalonId/clients';

/// 25 rows → page 0 holds 20, page 1 holds 5. Row 0 is the rated registered
/// client, row 1 a guest, the rest unrated registered clients.
void _seedRoster(FakeBackend fb) {
  fb.clientRows
    ..clear()
    ..add(<String, dynamic>{
      'kind': 'REGISTERED',
      'userId': 'u-oksana',
      'displayName': 'Оксана Мельник',
      'lastVisitAt': '2026-06-07T10:00:00Z',
      'nextVisitAt': '2026-06-20T12:00:00Z',
      'completedVisits': 9,
      'ratingAvg': 4.9,
      'ratingCount': 12,
      'blocked': false,
    })
    ..add(<String, dynamic>{
      'kind': 'GUEST',
      'guestBookingId': 'b-iryna',
      'displayName': 'Ірина Коваль',
      'lastVisitAt': '2026-06-01T10:00:00Z',
      'completedVisits': 2,
      'ratingCount': 0,
      'blocked': false,
    });
  for (int i = 2; i < 25; i++) {
    fb.clientRows.add(<String, dynamic>{
      'kind': 'REGISTERED',
      'userId': 'u-$i',
      'displayName': 'Клієнтка Номер$i',
      'lastVisitAt':
          '2026-05-${((i % 27) + 1).toString().padLeft(2, '0')}T10:00:00Z',
      'completedVisits': 1,
      'ratingCount': 0,
      'blocked': false,
    });
  }
}

Finder _row(String id) => find.byKey(Key('client-row-$id'));

/// Waits for the list, then drains the tab transition — mid-fade BOTH tabs'
/// bars are mounted, which makes single-bar finders ambiguous.
Future<void> _waitForList(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(ClientsScreen.listKey),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.settle(tester);
}

/// Types [text] into the search field and drives the debounce `Timer`.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(ClientsScreen.searchKey), text);
  await tester.pump();
  await tester.pump(kClientSearchDebounce);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('(a) SALON_OWNER: shell «Клієнти» → list → search → page 2 → '
      'row opens the card → back keeps the tab', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      _seedRoster(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));
      expect(
        fb.clientListCalls,
        isEmpty,
        reason: 'the tab is lazy: nothing is fetched before it is opened',
      );

      // The bar has 5 destinations and «Клієнти» is the 4th (index 3).
      expect(find.byKey(const Key('salon-nav-tile-4')), findsOneWidget);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await _waitForList(tester);

      expect(
        tester
            .widget<SalonBottomNav>(
              find.byKey(const Key('salon-shell-bottom-nav')),
            )
            .currentIndex,
        3,
      );
      // The salon-wide endpoint, FLAT paging, no `q`, no `masterId`.
      final ClientListCall first = fb.clientListCalls.first;
      expect(first.path, _kSalonPath);
      expect(first.page, 0);
      expect(first.size, 20);
      expect(first.q, isNull);
      expect(first.masterId, isNull);

      // Rows: rated registered client with both short dates, a guest without
      // any kind label, and no phone / completed count in the tree.
      expect(_row('u-oksana'), findsOneWidget);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Оксана Мельник'), findsOneWidget);
      expect(find.text('4.9'), findsOneWidget);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Ост.: 7 чер'), findsOneWidget);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Наст.: сб, 20 чер, 15:00'), findsOneWidget);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Запис за посиланням'), findsNothing);
      expect(find.textContaining('+380'), findsNothing);
      expect(_row('b-iryna'), findsOneWidget);

      // ── search ────────────────────────────────────────────────────────
      final int beforeShort = fb.clientListCalls.length;
      await _search(tester, 'О'); // 1 char: error line, NO request
      expect(fb.clientListCalls.length, beforeShort);
      expect(
        find.byKey(const Key('search_query_min_length_hint')),
        findsOneWidget,
      );

      await _search(tester, 'Мел');
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.clientListCalls.last.q == 'Мел',
        description: 'the debounced search request',
      );
      await AppHarness.settle(tester);
      expect(fb.clientListCalls.last.page, 0);
      expect(_row('u-oksana'), findsOneWidget);
      expect(_row('b-iryna'), findsNothing);
      expect(
        find.byKey(const Key('search_query_min_length_hint')),
        findsNothing,
      );

      // No match → notice, the field stays.
      await _search(tester, 'Яяяя');
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(ClientsScreen.noMatchKey),
      );
      expect(find.byKey(ClientsScreen.searchKey), findsOneWidget);

      // Clearing the box drops `q` and brings the full roster back.
      await _search(tester, '');
      await AppHarness.pumpUntilCondition(
        tester,
        () =>
            fb.clientListCalls.last.q == null &&
            _row('u-oksana').evaluate().isNotEmpty,
        description: 'the unfiltered list after clearing the search',
      );

      // ── paging ────────────────────────────────────────────────────────
      expect(
        fb.clientListCalls.where((ClientListCall c) => c.page == 1),
        isEmpty,
      );
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -3000),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.clientListCalls.any((ClientListCall c) => c.page == 1),
        description: 'page 2 requested on scroll',
      );
      final ClientListCall second = fb.clientListCalls.firstWhere(
        (ClientListCall c) => c.page == 1,
      );
      expect(second.path, _kSalonPath);
      expect(second.q, isNull);
      // The list is lazy: let page 2 land, then scroll its tail into the
      // 800x600 viewport before asserting the last row exists.
      await AppHarness.settle(tester);
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -3000),
      );
      await AppHarness.pumpUntilFound(tester, _row('u-24'));
      expect(_row('u-24'), findsOneWidget, reason: 'row 25 came with page 2');

      // The list is exhausted: no page 3.
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -3000),
      );
      await AppHarness.settle(tester);
      expect(
        fb.clientListCalls.where((ClientListCall c) => c.page == 2),
        isEmpty,
      );

      // ── row → card → back ─────────────────────────────────────────────
      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, 6000),
      );
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(tester, _row('u-oksana'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ClientCardPlaceholderScreen),
      );
      AppHarness.expectLocation(
        router,
        '/salons/$_kSalonId/clients/user/u-oksana',
      );

      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardPlaceholderScreen.backKey),
      );
      await AppHarness.settle(tester);
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(find.byKey(ClientsScreen.listKey), findsOneWidget);
      expect(
        tester
            .widget<SalonBottomNav>(
              find.byKey(const Key('salon-shell-bottom-nav')),
            )
            .currentIndex,
        3,
        reason: 'back returns to «Клієнти», not «Салон»',
      );
    });
  });

  testWidgets('(a2) a guest row opens …/guest/:bookingId', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..wireClientList();
      _seedRoster(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-3')),
      );
      await _waitForList(tester);
      await AppHarness.tapVisible(tester, _row('b-iryna'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ClientCardPlaceholderScreen),
      );
      AppHarness.expectLocation(
        router,
        '/salons/$_kSalonId/clients/guest/b-iryna',
      );
    });
  });

  testWidgets('(a3) SALON_OWNER «Профіль» (index 4) still leaves the shell for '
      'owner master mode', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..hasMasterProfile = true
        ..wireClientList();
      _seedRoster(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-4')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(OwnerOwnProfileScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      expect(find.byType(SalonShellScreen), findsNothing);
    });
  });

  testWidgets('(b) INDEPENDENT_MASTER: master bar «Клієнти» → '
      '/masters/me/clients', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..wireClientList();
      _seedRoster(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);
      expect(find.byType(MasterProfileScreen), findsOneWidget);
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await _waitForList(tester);

      AppHarness.expectLocation(router, RouteNames.masterClients);
      expect(
        tester
            .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
            .activeIndex,
        3,
      );
      expect(fb.clientListCalls.first.path, _kMasterPath);
      expect(fb.clientListCalls.first.masterId, isNull);
      expect(_row('u-oksana'), findsOneWidget);

      // A guest row → the guest card route below the master list.
      await AppHarness.tapVisible(tester, _row('b-iryna'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ClientCardPlaceholderScreen),
      );
      AppHarness.expectLocation(router, '/master/clients/guest/b-iryna');
      await AppHarness.tapVisible(
        tester,
        find.byKey(ClientCardPlaceholderScreen.backKey),
      );
      await AppHarness.settle(tester);

      // «Профіль» is now index 4 and still lands on the profile.
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-4')),
      );
      await AppHarness.pumpUntilFound(tester, find.byType(MasterProfileScreen));
      AppHarness.expectLocation(router, RouteNames.masterProfile);
    });
  });

  testWidgets('(c) SALON_MASTER: «Клієнти» → /staff/clients → '
      '/masters/me/clients, never the salon endpoint', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend(
        masterRowId: 'master-removable',
        masterSalonId: 'salon-xyz',
      )..wireClientList(salonIds: const <String>[_kSalonId, 'salon-xyz']);
      _seedRoster(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
      await AppHarness.settle(tester);
      expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
      AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await _waitForList(tester);

      AppHarness.expectLocation(router, RouteNames.salonMasterClients);
      expect(fb.clientListCalls, isNotEmpty);
      expect(
        fb.clientListCalls.every((ClientListCall c) => c.path == _kMasterPath),
        isTrue,
        reason:
            'a SALON_MASTER lists the master\'s OWN clients — the salon '
            'endpoint is owner / admin only (403)',
      );
      expect(_row('u-oksana'), findsOneWidget);

      await AppHarness.tapVisible(tester, _row('u-oksana'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ClientCardPlaceholderScreen),
      );
      AppHarness.expectLocation(router, '/staff/clients/user/u-oksana');
    });
  });

  testWidgets('(d) owner master mode: «Клієнти» → the SALON endpoint with '
      'masterId = the owner\'s own master row', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(masterRowId: _kOwnerMasterRowId, masterSalonId: _kSalonId)
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true
            ..wireClientList();
      _seedRoster(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

      // Enter master mode through «Профіль» (index 4).
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('salon-nav-tile-4')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(OwnerOwnProfileScreen),
        timeout: const Duration(seconds: 20),
      );
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-3')),
      );
      await _waitForList(tester);

      AppHarness.expectLocation(router, RouteNames.ownerMasterClients);
      expect(
        tester
            .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
            .activeIndex,
        3,
      );
      final ClientListCall call = fb.clientListCalls.first;
      expect(call.path, _kSalonPath);
      expect(call.masterId, _kOwnerMasterRowId);
      expect(find.byType(SalonShellScreen), findsNothing);

      // The card route is the salon-scoped one, narrowed by ?masterId=.
      await AppHarness.tapVisible(tester, _row('u-oksana'));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ClientCardPlaceholderScreen),
      );
      AppHarness.expectLocation(
        router,
        '/salons/$_kSalonId/clients/user/u-oksana?masterId=$_kOwnerMasterRowId',
      );
    });
  });

  testWidgets(
    '(e) an EMPTY roster shows the notice and hides the search field',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()..wireClientList(); // no rows
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-3')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(ClientsScreen.emptyKey),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);

        AppHarness.expectLocation(router, RouteNames.masterClients);
        expect(fb.clientListCalls.first.path, _kMasterPath);
        expect(find.byKey(ClientsScreen.searchKey), findsNothing);
        expect(find.byKey(ClientsScreen.listKey), findsNothing);
      });
    },
  );

  testWidgets(
    '(f) search over-length is cut to 50 on the wire; a failed page 2 '
    'keeps the list and is not hammered',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()..wireClientList();
        _seedRoster(fb);
        await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-3')),
        );
        await _waitForList(tester);

        // 60 chars typed → the field keeps 50 → exactly one 50-char `q`.
        await _search(tester, 'я' * 60);
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.clientListCalls.last.q != null,
          description: 'the debounced search request',
        );
        expect(fb.clientListCalls.last.q, 'я' * 50);
        expect(
          fb.clientListCalls.every(
            (ClientListCall c) => (c.q ?? '').length <= 50,
          ),
          isTrue,
        );

        // Back to the full roster, then fail page 2.
        await _search(tester, '');
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              fb.clientListCalls.last.q == null &&
              _row('u-oksana').evaluate().isNotEmpty,
          description: 'the unfiltered list after clearing the search',
        );
        fb.clientFailPages.add(1);
        await tester.drag(
          find.byKey(ClientsScreen.listKey),
          const Offset(0, -3000),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.clientListCalls.any((ClientListCall c) => c.page == 1),
          description: 'page 2 requested on scroll',
        );
        await AppHarness.settle(tester);
        final int page2 = fb.clientListCalls
            .where((ClientListCall c) => c.page == 1)
            .length;

        expect(find.byKey(ClientsScreen.errorKey), findsNothing);
        expect(find.byKey(ClientsScreen.listKey), findsOneWidget);
        expect(
          find.byKey(const Key('my_bookings_load_more_spinner')),
          findsNothing,
        );
        await tester.drag(
          find.byKey(ClientsScreen.listKey),
          const Offset(0, -300),
        );
        await AppHarness.settle(tester);
        expect(
          fb.clientListCalls.where((ClientListCall c) => c.page == 1),
          hasLength(page2),
          reason: 'no retry storm on scroll',
        );

        // The append failure has a UI: tap the retry footer, page 2 loads.
        expect(
          find.byKey(ClientsScreen.loadMoreRetryKey),
          findsOneWidget,
          reason: 'the failed page 2 shows a retry footer',
        );
        expect(_row('u-24'), findsNothing, reason: 'page 2 has not landed');
        fb.clientFailPages.clear();
        await AppHarness.tapVisible(
          tester,
          find.byKey(ClientsScreen.loadMoreRetryKey),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              fb.clientListCalls
                  .where((ClientListCall c) => c.page == 1)
                  .length ==
              page2 + 1,
          description: 'page 2 re-requested by the retry footer',
        );
        await AppHarness.settle(tester);
        expect(find.byKey(ClientsScreen.loadMoreRetryKey), findsNothing);
        await tester.drag(
          find.byKey(ClientsScreen.listKey),
          const Offset(0, -3000),
        );
        await AppHarness.settle(tester);
        expect(_row('u-24'), findsOneWidget, reason: 'row 25 came with page 2');
      });
    },
  );
}
