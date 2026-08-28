// Regression — `/salons/:salonId` must stay an INERT, bare-path route: it may
// never again seed a tab index or a service filter from the URL.
//
// WHAT WAS DELETED, AND WHY THIS FILE EXISTS
// -------------------------------------------
// An earlier cut let the salon-arm Beauty Passport favourite deep-link into
// the salon profile pre-filtered to one service, via
// `RouteNames.salonPublicProfile(salonId, serviceId: …)` →
// `/salons/:id?serviceId=X&tab=masters`. `app_router.dart` parsed those two
// query params into `PublicSalonProfileScreen.initialServiceId` /
// `.initialMastersTab`, and the screen resolved them against the catalogue
// once (`_applyDeepLinkFilter`) to land on tab 1 with a «Послуга: X» chip.
//
// That was a second, parallel "masters who perform this service" UI sitting on
// top of the salon booking flow's step 2, which already IS exactly that. The
// whole mechanism — route param, query assembly, router parsing, screen fields
// and the one-shot seed — was deleted; the CTA now pushes
// `RouteNames.salonBookingMasters` instead.
//
// `salon_profile_swipe_back_test.dart` pins only the STRING side
// (`RouteNames.salonPublicProfile('abc')` emits no `?`) — and that pin is
// MUTATION-VERIFIED VACUOUS for this regression: restore the deleted
// `{String? serviceId}` overload verbatim and it stays GREEN, because the
// no-arg call it exercises returned a bare path while the overload existed
// too. It constrains the URL BUILDER's default shape, nothing more. Nothing
// in it stops a future change from re-adding `initialServiceId:
// state.uri.queryParameters['serviceId']` to the router plus a matching seed
// to the screen.
//
// So this file pins the BEHAVIOUR instead, in two groups:
//
//   1. "…query is INERT" — a URL literally carrying the OLD
//      `?serviceId=…&tab=masters` selects no tab, seeds no filter, and fires
//      no coverage fan-out. It drives the REAL `/salons/:salonId` builder
//      closure lifted straight out of `appRouterProvider` (see
//      [_realSalonProfileRoute]), so re-added query parsing flows through it.
//      All three assertions verified RED against the genuine pre-deletion
//      code restored from git.
//   2. "a plain entry auto-selects nothing" — the ordinary salon-card tap is
//      equally unfiltered. This catches a seed re-added to the SCREEN with
//      the router left alone; verified RED under an unconditional `_tab = 1`.
//
// Each assertion gets its own `testWidgets` on purpose — see [_openProfile].
//
// The service→masters filter the client reaches by TAPPING a service in the
// profile's own "Послуги" tab is a DIFFERENT, unaffected feature — it keeps
// its eight tap-driven groups in `public_salon_profile_screen_test.dart` and
// its own end-to-end guard in
// `integration_test/salon_service_filter_flow_test.dart`. Nothing here weakens
// it: every assertion below is scoped to ENTRY, before any interaction.

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/bookable_master_assignment.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_portfolio_photo.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';

const _kSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон у центрі.',
);

const _kMasters = <SalonMasterSummary>[
  SalonMasterSummary(
    masterId: 'master-1',
    firstName: 'Олена',
    lastName: 'Ковальчук',
    avgRating: 4.9,
    reviewCount: 12,
    type: MasterType.salonMaster,
  ),
  SalonMasterSummary(
    masterId: 'master-2',
    firstName: 'Богдан',
    lastName: 'Мороз',
    avgRating: 4.7,
    reviewCount: 4,
    type: MasterType.salonMaster,
  ),
];

/// `svc-1` is the id the deleted deep link used to carry, and it IS a real
/// catalogue entry — so a resurrected seed would RESOLVE it and show a chip
/// rather than silently give up. Using a resolvable id is what makes test 1
/// able to fail.
const _kCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'NAILS',
    displayName: 'Манікюр',
    count: 1,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-1',
        name: 'Манікюр з покриттям',
        durationLabel: '1 год 30 хв',
        priceDisplay: '500 ₴',
      ),
    ],
  ),
];

const _kSummary = SalonReviewSummary(
  avgRating: 4.9,
  reviewCount: 2,
  distribution: <int>[1, 1, 0, 0, 0],
);

const _kUser = User(
  id: 'c1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Client',
  lastName: 'User',
);

/// Always-authenticated CLIENT — the profile is CLIENT-guarded.
class _ClientAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _kUser, accessToken: 'test-token');
}

/// `appRouterProvider` eagerly subscribes to [authProvider]; settle it without
/// touching the real Dio / secure-storage stack.
class _UnauthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
    return const AuthSession.unauthenticated();
  }
}

class _NoopFavoriteRepository implements FavoriteRepository {
  @override
  Future<void> add(FavoriteTarget target) async {}

  @override
  Future<void> remove(FavoriteTarget target) async {}

  // Phase 111 — routing-only test; the list calls are never reached.
  @override
  Future<List<FavoriteItem>> getFavoriteMasters() async =>
      const <FavoriteItem>[];

  @override
  Future<List<FavoriteItem>> getFavoriteSalons() async =>
      const <FavoriteItem>[];
}

/// In-memory [SalonRepository] whose ONLY interesting property is
/// [bookableMastersCalls] — the per-service coverage fan-out counter test 2
/// asserts against. Every other loader returns a settled fixture so the screen
/// reaches its data state with no network and no unbounded shimmer.
class _CountingSalonRepository implements SalonRepository {
  /// Number of `GET /salons/{id}/services/{serviceDefId}/masters` calls, i.e.
  /// how many times the service→masters coverage fan-out actually ran. MUST
  /// stay 0 on a plain profile entry: that fan-out exists only behind a
  /// service filter, and on entry there is no filter.
  int bookableMastersCalls = 0;

  /// Every `serviceDefId` [getBookableMasters] was asked about, in order —
  /// reported in the failure message so a regression names the offending id
  /// instead of only a count.
  final List<String> bookableMastersServiceIds = <String>[];

  @override
  Future<void> create({required SalonCreateDto dto}) async {}

  // Phase 21.1 — this screen (the PUBLIC/client profile) never calls the
  // owner-scoped `GET /salons/mine`; empty keeps the contract satisfied.
  @override
  Future<List<Salon>> getMySalons() async => const <Salon>[];

  @override
  Future<Salon> getSalonById(String salonId) async => _kSalon;

  @override
  Future<List<SalonMasterSummary>> getSalonMasters(String salonId) async =>
      _kMasters;

  @override
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  ) async => _kCatalog;

  @override
  Future<SalonReviewSummary> getSalonReviewSummary(String salonId) async =>
      _kSummary;

  @override
  Future<List<SalonReviewItem>> getSalonReviews({
    required String salonId,
    required SalonReviewSort sort,
    int page = 0,
    int size = kSalonReviewsPageSize,
  }) async => const <SalonReviewItem>[];

  @override
  Future<List<SalonPortfolioPhoto>> getSalonPortfolio(String salonId) async =>
      const <SalonPortfolioPhoto>[];

  @override
  Future<List<BookableMasterAssignment>> getBookableMasters({
    required String salonId,
    required String serviceDefId,
  }) async {
    bookableMastersCalls++;
    bookableMastersServiceIds.add(serviceDefId);
    return const <BookableMasterAssignment>[];
  }

  // Phase 21.2 — owner/admin write paths. This fake backs the CLIENT-facing
  // read-only profile route under test here; neither is ever called.
  @override
  Future<Salon> updateSalon(String salonId, UpdateSalonRequest request) async =>
      throw UnimplementedError(
        '_CountingSalonRepository.updateSalon is not stubbed — this fake '
        'backs the CLIENT-facing read-only profile route.',
      );

  @override
  Future<void> deleteSalon(String salonId) async => throw UnimplementedError(
    '_CountingSalonRepository.deleteSalon is not stubbed — this fake backs '
    'the CLIENT-facing read-only profile route.',
  );
}

List<Object> _overrides(_CountingSalonRepository repo) => <Object>[
  authProvider.overrideWith(_ClientAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
  favoriteRepositoryProvider.overrideWithValue(_NoopFavoriteRepository()),
];

// ---------------------------------------------------------------------------
// The REAL route builder, lifted out of appRouterProvider
// ---------------------------------------------------------------------------

/// Recursively finds the first [GoRoute] (at any nesting depth) with [path].
/// Same helper shape as `salon_profile_swipe_back_test.dart`'s.
GoRoute? _findRoute(List<RouteBase> routes, String path) {
  for (final RouteBase route in routes) {
    if (route is GoRoute && route.path == path) return route;
    final GoRoute? nested = _findRoute(route.routes, path);
    if (nested != null) return nested;
  }
  return null;
}

/// Returns the PRODUCTION `/salons/:salonId` [GoRoute] out of the real
/// `appRouterProvider` configuration.
///
/// Lifting the genuine `builder:` closure (rather than re-declaring a
/// look-alike here) is the whole point: the assertion below is only load-
/// bearing because a re-added `initialServiceId: state.uri
/// .queryParameters['serviceId']` inside `app_router.dart` runs INSIDE this
/// exact closure. A hand-written stand-in would keep passing through any such
/// regression.
GoRoute _realSalonProfileRoute() {
  final ProviderContainer container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(_UnauthNotifier.new),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  final GoRouter router = container.read(appRouterProvider);
  addTearDown(router.dispose);

  final GoRoute? route = _findRoute(
    router.configuration.routes,
    '/salons/:salonId',
  );
  expect(
    route,
    isNotNull,
    reason: 'Expected a registered GoRoute for /salons/:salonId',
  );
  expect(
    route!.builder,
    isNotNull,
    reason:
        'This test drives the production builder closure directly — a route '
        'that moved to pageBuilder: would silently stop being exercised '
        'here (and would separately fail salon_profile_swipe_back_test.dart).',
  );
  return route;
}

/// A bare probe router that mounts the REAL builder at the REAL path, with no
/// auth shell / redirect chain in the way. `initialLocation` is the URL under
/// test, so the query string (if any) reaches `state.uri` exactly as it would
/// from a real deep link.
GoRouter _probeRouter(GoRoute real, String location) => GoRouter(
  initialLocation: location,
  routes: <RouteBase>[GoRoute(path: real.path, builder: real.builder)],
);

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the REAL `/salons/:salonId` builder at [location] and returns the
/// repository the screen fetched through, so each test can assert ONE thing.
///
/// WHY EACH ASSERTION GETS ITS OWN `testWidgets` RATHER THAN SHARING A BODY:
/// `expect` throws on the first failure, so a single test bundling
/// tab + chip + coverage-count would only ever be PROVEN load-bearing on
/// whichever assertion happens to be first — the other two would be
/// unfalsified passengers, exactly the vacuous shape this repo has been
/// burned by. Split, each one is separately shown red under the mutation that
/// targets it.
Future<_CountingSalonRepository> _openProfile(
  WidgetTester tester,
  String location,
) async {
  await _pumpTall(tester);
  final GoRoute real = _realSalonProfileRoute();
  final _CountingSalonRepository repo = _CountingSalonRepository();

  await tester.pumpRoutedApp(
    _probeRouter(real, location),
    overrides: _overrides(repo),
  );
  await tester.pumpAndSettle();

  // The screen is genuinely up. Without this, every `findsNothing` below
  // would pass vacuously on a blank/error page — the "assertion that cannot
  // fail" trap.
  expect(
    find.byKey(const Key('salon-profile-name')),
    findsOneWidget,
    reason:
        'the profile must actually render for these tests to mean anything — '
        'the negative assertions are only evidence if the screen is up',
  );
  return repo;
}

const String _kDeepLinkUrl = '/salons/$_kSalonId?serviceId=svc-1&tab=masters';
const String _kBareUrl = '/salons/$_kSalonId';

void main() {
  // =========================================================================
  // The DELETED deep link, replayed verbatim, must do nothing.
  // =========================================================================
  group(
    'a URL carrying the deleted ?serviceId=…&tab=masters query is INERT',
    () {
      testWidgets(
        'it does not select a tab — the profile opens on "Про салон"',
        (tester) async {
          await _openProfile(tester, _kDeepLinkUrl);

          // `salon-tab-body-<key>` is the AnimatedSwitcher child's ValueKey, so
          // exactly one exists at a time — a resurrected seed flips which.
          expect(
            find.byKey(const ValueKey<String>('salon-tab-body-about')),
            findsOneWidget,
            reason:
                'the URL query must not select a tab — a resurrected '
                'initialMastersTab/initialServiceId seed lands on '
                'salon-tab-body-masters instead',
          );
          expect(
            find.byKey(const ValueKey<String>('salon-tab-body-masters')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('it does not seed a service filter — no «Послуга» chip', (
        tester,
      ) async {
        await _openProfile(tester, _kDeepLinkUrl);

        expect(
          find.byKey(const Key('salon-masters-filter-chip')),
          findsNothing,
          reason:
              'svc-1 IS a resolvable catalogue entry in this fixture, so a '
              'resurrected deep-link seed WOULD resolve it and render a named '
              'chip — this assertion is falsifiable, not decorative',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('it does not fire the per-service coverage fan-out', (
        tester,
      ) async {
        final _CountingSalonRepository repo = await _openProfile(
          tester,
          _kDeepLinkUrl,
        );

        expect(
          repo.bookableMastersCalls,
          0,
          reason:
              'a seeded filter fans out one bookable-masters call per selected '
              'service; got calls for ${repo.bookableMastersServiceIds}',
        );
        expect(tester.takeException(), isNull);
      });
    },
  );

  // =========================================================================
  // The ORDINARY entry (a salon result-card tap) must be equally unfiltered.
  // Guards the screen side alone: a seed re-added in `initState`/`build` with
  // the router left untouched shows up here and nowhere else.
  // =========================================================================
  group('a plain /salons/:salonId entry auto-selects nothing', () {
    testWidgets('opens on "Про салон", never the Майстри tab', (tester) async {
      await _openProfile(tester, _kBareUrl);

      expect(
        find.byKey(const ValueKey<String>('salon-tab-body-about')),
        findsOneWidget,
        reason:
            'entry must never auto-switch to the Майстри tab — a behaviour '
            'guard, not a route-string guard',
      );
      expect(
        find.byKey(const ValueKey<String>('salon-tab-body-masters')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('applies no service filter on entry', (tester) async {
      await _openProfile(tester, _kBareUrl);

      expect(
        find.byKey(const Key('salon-masters-filter-chip')),
        findsNothing,
        reason: 'entry must never auto-apply a service filter',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('never fires the per-service coverage fan-out', (tester) async {
      final _CountingSalonRepository repo = await _openProfile(
        tester,
        _kBareUrl,
      );

      expect(
        repo.bookableMastersCalls,
        0,
        reason:
            'the coverage fan-out is filter-driven only — firing it on entry '
            'means something auto-selected a service; got calls for '
            '${repo.bookableMastersServiceIds}',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
