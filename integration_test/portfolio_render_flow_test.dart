// Phase 404 (9.9) — fake-backed E2E: the independent master's own profile
// renders the REAL portfolio (not placeholder tiles) over the shared
// `FakeBackend` (`wirePortfolio: true` — the phase-403 public read
// `GET /masters/{masterRowId}/portfolio`).
//
// Asserts observable outcomes only: one tile per stored row, found by the
// per-photo key `portfolio-photo-<id>`, in the stored (newest-first) order,
// and the read hitting the master path; an empty portfolio shows the own
// empty-state line instead of tiles.
//
// mobile-qa extension (2026-10-12) — the spec's remaining locked rules, end to
// end over the REAL router + repositories + generated clients:
//   • salon management «Про салон» shows the SALON's photos for the owner
//     (`salon-owner-1`, reached via their salon shell) AND the bound admin
//     (`salon-admin-1`);
//   • a CLIENT on an independent master's public profile (`master-aaa`) sees
//     the photos; with none, NO section at all (the read is proven to have
//     happened, so the absence is not an unwired-route artefact);
//   • a CLIENT on a salon-affiliated master's public profile gets no rail and
//     no portfolio request ever leaves the app;
//   • the owner / admin / salon-master own profiles (and owner master mode)
//     never request a portfolio.
// "No request" is observed by an interceptor on the app's real Dio
// ([_recordPortfolioRequests]) — it sees UNMATCHED routes too, which the
// fake's per-route counters cannot. Every negative is paired with a positive
// control in the same harness shape.
//
// Assertions target per-photo KEYS after scrolling the rail into view (never
// "all N tiles exist at once"), so they survive the rail becoming a lazy,
// capped horizontal list.
//
// Runs headless: `flutter test integration_test/portfolio_render_flow_test.dart
// -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/admin_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  Future<FakeBackend> bootMaster(
    WidgetTester tester,
    void Function(FakeBackend fb) seed,
  ) async {
    final FakeBackend fb = FakeBackend(wirePortfolio: true)
      ..currentRole = UserRole.independentMaster;
    seed(fb);
    await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await AppHarness.pumpUntilFound(tester, find.byType(MasterProfileScreen));
    await tester.pumpAndSettle();
    expect(find.byType(MasterProfileScreen), findsOneWidget);
    return fb;
  }

  testWidgets('INDEPENDENT_MASTER own profile: real tiles per stored photo, '
      'in stored order, read from the master portfolio path', (tester) async {
    final FakeBackend fb = await bootMaster(tester, (FakeBackend fb) {
      fb.masterPortfolioRows
        ..add(fb.portfolioRow('MASTER', fb.masterRowId))
        ..add(fb.portfolioRow('MASTER', fb.masterRowId));
    });

    final Finder first = find.byKey(const Key('portfolio-photo-pf-1'));
    await tester.scrollUntilVisible(
      first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Per-key, in-order — not a global tile count, which a lazy rail (R1)
    // only satisfies while every tile happens to be inside the viewport.
    _expectTilesInOrder(tester, const <String>['pf-1', 'pf-2']);
    expect(
      fb.portfolioReadUris.map((Uri u) => u.path),
      everyElement('/api/v1/masters/${fb.masterRowId}/portfolio'),
    );
    expect(fb.portfolioReadUris, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('INDEPENDENT_MASTER own profile, empty portfolio: the own '
      'empty-state line, no tiles', (tester) async {
    await bootMaster(tester, (_) {});

    final Finder empty = find.byKey(const Key('portfolio-rail-empty'));
    await tester.scrollUntilVisible(
      empty,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(empty, findsOneWidget);
    expect(find.byType(PortfolioTile), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── Salon management «Про салон» — owner AND admin see the SALON's photos ──

  testWidgets('SALON_OWNER «Про салон»: the salon\'s real photos, keyed per '
      'photo, in stored order; read for THIS salon, never a master path', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend(wirePortfolio: true)
        ..currentRole = UserRole.salonOwner;
      fb.ownerSalonPortfolioRows
        ..add(fb.portfolioRow('SALON', FakeBackend.kOwnerSalonId))
        ..add(fb.portfolioRow('SALON', FakeBackend.kOwnerSalonId));
      // A regression reading the owner's personal (master) portfolio would
      // find data here — the path assertion below catches it.
      fb.masterPortfolioRows.add(fb.portfolioRow('MASTER', fb.masterRowId));
      final List<String> requests = _recordPortfolioRequests(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      // The owner's manage route lands on their salon shell, whose «Профіль»
      // slot IS the management screen.
      router.go(RouteNames.salonManage(FakeBackend.kOwnerSalonId));
      await AppHarness.settle(tester);
      expect(find.byType(SalonManagementProfileScreen), findsOneWidget);

      await _scrollIntoView(tester, const Key('portfolio-photo-pf-1'));
      _expectTilesInOrder(tester, const <String>['pf-1', 'pf-2']);
      expect(
        find.descendant(
          of: find.byKey(const Key('salon-manage-portfolio')),
          matching: find.byKey(const Key('portfolio-photo-pf-1')),
        ),
        findsOneWidget,
      );
      // pf-3 is the MASTER row seeded third above (ids are sequential) —
      // the viewer's personal portfolio must not leak onto «Про салон».
      expect(find.byKey(const Key('portfolio-photo-pf-3')), findsNothing);
      expect(
        requests,
        everyElement(
          'GET /api/v1/salons/${FakeBackend.kOwnerSalonId}/portfolio',
        ),
      );
      expect(requests, isNotEmpty);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('SALON_ADMIN «Про салон»: the bound salon\'s real photos, read '
      'from that salon\'s path only', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend(wirePortfolio: true)
        ..currentRole = UserRole.salonAdmin;
      fb.adminSalonPortfolioRows
        ..add(fb.portfolioRow('SALON', 'salon-admin-1'))
        ..add(fb.portfolioRow('SALON', 'salon-admin-1'));
      // A regression that read the admin's OWN (master) portfolio would find
      // data here and render it — the path assertion below catches it.
      fb.masterPortfolioRows.add(fb.portfolioRow('MASTER', fb.masterRowId));
      final List<String> requests = _recordPortfolioRequests(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
      await AppHarness.settle(tester);

      router.go(RouteNames.salonManage('salon-admin-1'));
      await AppHarness.settle(tester);
      expect(find.byType(SalonManagementProfileScreen), findsOneWidget);

      await _scrollIntoView(tester, const Key('portfolio-photo-pf-1'));
      _expectTilesInOrder(tester, const <String>['pf-1', 'pf-2']);
      // pf-3 is the MASTER row seeded third above (ids are sequential) —
      // the viewer's personal portfolio must not leak onto «Про салон».
      expect(find.byKey(const Key('portfolio-photo-pf-3')), findsNothing);
      expect(
        requests,
        everyElement('GET /api/v1/salons/salon-admin-1/portfolio'),
      );
      expect(requests, isNotEmpty);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── CLIENT on a public master profile ─────────────────────────────────────

  testWidgets('CLIENT on an independent master\'s public profile sees the '
      'real photos, read from that master\'s public path', (tester) async {
    final _ClientHarness h = await _bootClientOnMasterAaa(tester, (fb) {
      fb.publicMasterPortfolioRows
        ..add(fb.portfolioRow('MASTER', 'master-aaa'))
        ..add(fb.portfolioRow('MASTER', 'master-aaa'));
    });

    await _scrollIntoView(tester, const Key('portfolio-photo-pf-1'));
    _expectTilesInOrder(tester, const <String>['pf-1', 'pf-2']);
    expect(
      find.descendant(
        of: find.byKey(const Key('public-master-profile-portfolio')),
        matching: find.byKey(const Key('portfolio-photo-pf-2')),
      ),
      findsOneWidget,
    );
    expect(
      h.requests,
      everyElement('GET /api/v1/masters/master-aaa/portfolio'),
    );
    expect(h.requests, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('CLIENT on an independent master with NO photos: the read '
      'happened and answered empty, and no section renders at all', (
    tester,
  ) async {
    final _ClientHarness h = await _bootClientOnMasterAaa(tester, (_) {});

    // Positive controls: the About tab rendered, and the empty answer really
    // came over the wire (not an unwired-route error that also hides it).
    expect(
      find.byKey(const Key('public-master-profile-about-tab')),
      findsOneWidget,
    );
    expect(h.requests, contains('GET /api/v1/masters/master-aaa/portfolio'));
    expect(
      find.byKey(const Key('public-master-profile-portfolio')),
      findsNothing,
    );
    expect(find.byKey(const Key('portfolio-rail-empty')), findsNothing);
    expect(find.byKey(const Key('portfolio-rail-error')), findsNothing);
    expect(find.byType(PortfolioRail), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('CLIENT on a SALON_MASTER\'s public profile: no rail, and no '
      'portfolio request ever leaves the app', (tester) async {
    final _ClientHarness h = await _bootClientOnMasterAaa(tester, (fb) {
      fb.publicMasterTypeSalon = true;
      // Seeded so a regression that DID read would render tiles.
      fb.publicMasterPortfolioRows.add(fb.portfolioRow('MASTER', 'master-aaa'));
    });

    expect(
      find.byKey(const Key('public-master-profile-about-tab')),
      findsOneWidget,
    );
    expect(find.byType(PortfolioRail), findsNothing);
    expect(find.byType(PortfolioTile), findsNothing);
    expect(h.requests, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── Owner / admin / salon-master own profiles never request a portfolio ──

  for (final _OwnProfileCase c in <_OwnProfileCase>[
    const _OwnProfileCase(
      UserRole.salonOwner,
      RouteNames.ownerOwnProfile,
      OwnerOwnProfileScreen,
    ),
    const _OwnProfileCase(
      UserRole.salonOwner,
      RouteNames.ownerMasterProfile,
      OwnerOwnProfileScreen,
    ),
    const _OwnProfileCase(
      UserRole.salonAdmin,
      RouteNames.adminOwnProfile,
      AdminOwnProfileScreen,
    ),
    const _OwnProfileCase(
      UserRole.salonMaster,
      RouteNames.salonMasterProfile,
      SalonMasterProfileScreen,
    ),
  ]) {
    testWidgets('${c.role.name} own profile (${c.route}) requests no portfolio '
        'and renders no rail', (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend(wirePortfolio: true)
          ..currentRole = c.role;
        fb.masterPortfolioRows.add(fb.portfolioRow('MASTER', fb.masterRowId));
        final List<String> requests = _recordPortfolioRequests(fb);
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, c.role);
        await AppHarness.settle(tester);

        router.go(c.route);
        await AppHarness.settle(tester);

        expect(find.byType(c.screen), findsOneWidget);
        expect(find.byType(PortfolioRail), findsNothing);
        // Over the WHOLE session (the role's landing included — a salon
        // master lands ON this profile, so clearing after login would hide
        // its reads): no personal portfolio, read or write. A salon shell's
        // own «Про салон» may legitimately read the SALON's portfolio.
        expect(
          requests.where((String r) => !r.startsWith('GET /api/v1/salons/')),
          isEmpty,
        );
      });
    }, timeout: const Timeout(Duration(seconds: 90)));
  }
}

/// Records `METHOD path` of every request whose path mentions `portfolio`,
/// at the app's real [Dio] — matched or not by the fake's routes.
List<String> _recordPortfolioRequests(FakeBackend fb) {
  final List<String> log = <String>[];
  fb.dio.interceptors.insert(
    0,
    InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler handler) {
        if (o.uri.path.contains('portfolio')) {
          log.add('${o.method} ${o.uri.path}');
        }
        handler.next(o);
      },
    ),
  );
  return log;
}

/// Scrolls the profile's vertical scroll until [key] is built and visible.
Future<void> _scrollIntoView(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await AppHarness.settle(tester);
}

/// Each id's tile is on screen, left-to-right in [ids] order.
void _expectTilesInOrder(WidgetTester tester, List<String> ids) {
  double? previousX;
  for (final String id in ids) {
    final Finder tile = find.byKey(Key('portfolio-photo-$id'));
    expect(tile, findsOneWidget, reason: 'tile $id is rendered');
    final double x = tester.getTopLeft(tile).dx;
    if (previousX != null) {
      expect(x, greaterThan(previousX), reason: 'tile $id follows its peer');
    }
    previousX = x;
  }
}

final class _ClientHarness {
  const _ClientHarness(this.fb, this.requests);

  final FakeBackend fb;
  final List<String> requests;
}

Future<_ClientHarness> _bootClientOnMasterAaa(
  WidgetTester tester,
  void Function(FakeBackend fb) seed,
) async {
  final FakeBackend fb = FakeBackend(wirePortfolio: true)
    ..currentRole = UserRole.client;
  seed(fb);
  final List<String> requests = _recordPortfolioRequests(fb);
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.client);
  await AppHarness.settle(tester);

  unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('public-master-profile-about-tab')),
  );
  await AppHarness.settle(tester);
  expect(find.byType(PublicMasterProfileScreen), findsOneWidget);
  return _ClientHarness(fb, requests);
}

final class _OwnProfileCase {
  const _OwnProfileCase(this.role, this.route, this.screen);

  final UserRole role;
  final String route;
  final Type screen;
}
