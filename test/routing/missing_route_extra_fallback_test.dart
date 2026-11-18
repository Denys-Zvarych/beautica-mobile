// Sentry 162160464 (prod 1.9.1+13) — `_MissingRouteExtra` on the CLIENT
// SALON booking flow.
//
// `booking_stack_router_refresh_test.dart` pins the fallback on the master
// booking stack. This file pins it on the salon flow: a real `authRouterKey`
// change (the CLIENT's `salonId`, which no CLIENT redirect reads) fires
// `refreshListenable`; go_router re-parses the reported stack, drops every
// non-JSON `extra` (here `SalonBookingMasterSelectionArgs`) and does not run
// route-level `redirect:`s on the restored imperative pages. The master step
// must render the fallback and pop itself — back to the services step, whose
// bare-String `extra` the codec JSON-encodes and so keeps.
//
// WHAT THIS FILE DELIBERATELY DOES NOT TEST (measured 2026-11-18, reported as
// QA findings rather than faked here):
//   * the fallback's `go(fallbackRoute)` arm — a restored imperative page
//     always has its base match under it, so `canPop()` is true; a page that
//     is itself the base match keeps its `extra`, or is bounced by its own
//     route `redirect:` before the builder runs (a fallback-route mutation
//     stayed green);
//   * `_staffLanding` — both staff `extra` routes carry a bare String, which
//     survives the restore, so their fallback is never built (and its
//     signed-out → /login arm is pre-empted by the top-level auth redirect).
//
// FALSIFIED (2026-11-18): with the `/booking/salon/*` builders put back to
// `state.extra! as X`, the test goes RED on the null check.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/booking_links/presentation/master_nav_setup_hints_provider.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_salon_master_coverage.dart';
import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_media_upload_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

const String _kSalonId = 'salon-1';

const User _client = User(
  id: 'c1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Client',
  lastName: 'User',
);

const SalonBookingMasterSelectionArgs _masterArgs =
    SalonBookingMasterSelectionArgs(
      salonId: _kSalonId,
      selectedServiceIds: <String>['svc-1'],
    );

const Key _fallbackKey = Key('route_missing_extra_fallback');

/// Settles to the CLIENT session; the test then assigns `state` directly.
class _SettableAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _client, accessToken: 'token-0');

  void emit(User user) => state = AsyncData<AuthSession>(
    AuthSession.authenticated(user: user, accessToken: 'token-0'),
  );
}

class _SettledWishlistNotifier extends Wishlist {
  @override
  Future<List<WishlistService>> build() async => const <WishlistService>[];
}

Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  _SettableAuthNotifier auth,
) async {
  final ProviderContainer container = makeTestContainer(
    retry: (_, _) => null,
    overrides: [
      masterNavSetupHintsProvider.overrideWithValue(BookingLinkSetupHints.none),
      portfolioProvider.overrideWith2((_) => FixedPortfolioNotifier()),
      authProvider.overrideWith(() => auth),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
      wishlistProvider.overrideWith(_SettledWishlistNotifier.new),
      myRatingProvider.overrideWith((ref) async => const ClientRating()),
      salonServiceCatalogProvider.overrideWith((ref, salonId) async => []),
      salonMasterServiceCoverageProvider.overrideWith2(
        (_) => FakeSalonMasterServiceCoverage(
          () => salonCoverageOf(<String, Map<String, String>>{}),
        ),
      ),
      publicSalonProfileProvider(_kSalonId).overrideWith(
        (ref) => (
          const Salon(id: _kSalonId, name: 'Test Salon'),
          const <SalonMasterSummary>[],
        ),
      ),
    ],
  );
  final GoRouter router = container.read(appRouterProvider);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk', 'UA'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(router.state.matchedLocation, RouteNames.clientHome);
  return router;
}

void main() {
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  testWidgets(
    'CLIENT salon flow, master step over the services step: a router-key '
    'change drops the typed extra, nothing throws, and the fallback pops back '
    'to the services step, whose String extra survives',
    (tester) async {
      final _SettableAuthNotifier auth = _SettableAuthNotifier();
      final GoRouter router = await _pumpRouter(tester, auth);
      unawaited(
        router.push<void>(RouteNames.salonBookingServices, extra: _kSalonId),
      );
      await tester.pumpAndSettle();
      unawaited(
        router.push<void>(RouteNames.salonBookingMasters, extra: _masterArgs),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);

      final List<String> visited = <String>[router.state.matchedLocation];
      auth.emit(_client.copyWith(salonId: 'salon-x'));
      // Fixed frame budget, not a settle check: the restore is async
      // (route-information parsing), so "no frame scheduled" right after the
      // emit is not "done". Stepping catches a throw at the frame it happens.
      for (int i = 0; i < 60; i++) {
        // fixed-wait-ok: a frame-step clock, not a guess at completion — the
        // pumpAndSettle below is what waits for completion.
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: 'frame $i');
        final String loc = router.state.matchedLocation;
        if (visited.last != loc) visited.add(loc);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(visited, <String>[
        RouteNames.salonBookingMasters,
        RouteNames.salonBookingServices,
      ]);
      expect(router.state.matchedLocation, RouteNames.salonBookingServices);
      expect(find.byType(SalonMasterSelectionScreen), findsNothing);
      expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);
      expect(find.byKey(_fallbackKey), findsNothing);
    },
  );
}
