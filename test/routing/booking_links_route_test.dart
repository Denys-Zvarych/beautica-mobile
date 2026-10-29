// Phase 414 — `/settings/booking-links` route: role gate + hub wiring.
//
//   • auth gate (pure seam `authRedirectForLocation`): INDEPENDENT_MASTER,
//     SALON_OWNER, SALON_ADMIN admitted; SALON_MASTER / CLIENT bounced to
//     roleHomePath; signed out → login.
//   • the PRODUCTION router registers the route and builds BookingLinkScreen.
//   • the PRODUCTION hub routes pass `showBookingLinks: true` ONLY for
//     masterMenu; ownerSettings / adminSettings (salons reach the row from
//     salon «Налаштування» only — user decision 2026-10-29) and the salon
//     master's `/staff/settings` leave it `false`.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_screen.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

AsyncValue<AuthSession> _sessionFor(UserRole role) => AsyncData<AuthSession>(
  AuthSession.authenticated(
    user: User(
      id: 'u-${role.name}',
      email: '${role.name}@beautica.test',
      role: role,
      salonId: role == UserRole.salonAdmin ? 'salon-1' : null,
    ),
    accessToken: 'token',
  ),
);

GoRouter _productionRouter() {
  final ProviderContainer container = makeTestContainer(
    overrides: <Object>[
      authProvider.overrideWith(
        () => FixedRoleAuth(UserRole.independentMaster),
      ),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  return container.read(appRouterProvider);
}

/// Builds the production leaf widget for [location] (the builders under test
/// ignore their context, so any mounted context will do).
Widget _leafWidget(GoRouter router, BuildContext context, String location) {
  final RouteMatchList match = router.configuration.findMatch(
    Uri.parse(location),
  );
  expect(match.isError, isFalse, reason: '$location must be registered');
  final GoRoute route = match.last.route;
  final GoRouterWidgetBuilder? builder = route.builder;
  expect(builder, isNotNull, reason: '$location uses a builder');
  return builder!(
    context,
    router.configuration.buildTopLevelGoRouterState(match),
  );
}

void main() {
  group('auth gate on ${RouteNames.bookingLinks}', () {
    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      test('${role.name} is ADMITTED', () {
        expect(
          authRedirectForLocation(_sessionFor(role), RouteNames.bookingLinks),
          isNull,
        );
      });
    }

    for (final UserRole role in <UserRole>[
      UserRole.salonMaster,
      UserRole.client,
    ]) {
      test('${role.name} is BOUNCED to roleHomePath', () {
        expect(
          authRedirectForLocation(_sessionFor(role), RouteNames.bookingLinks),
          roleHomePath(role),
        );
      });
    }

    test('signed out is sent to login', () {
      expect(
        authRedirectForLocation(
          const AsyncData<AuthSession>(AuthSession.unauthenticated()),
          RouteNames.bookingLinks,
        ),
        RouteNames.login,
      );
    });

    test('the gate does not touch the plain ${RouteNames.settings} route', () {
      expect(
        authRedirectForLocation(
          _sessionFor(UserRole.salonMaster),
          RouteNames.settings,
        ),
        isNull,
      );
    });
  });

  testWidgets('production router: route builds BookingLinkScreen; hubs wire '
      'showBookingLinks per role', (tester) async {
    final GoRouter router = _productionRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(const SizedBox(key: Key('ctx')));
    final BuildContext context = tester.element(find.byKey(const Key('ctx')));

    expect(
      _leafWidget(router, context, RouteNames.bookingLinks),
      isA<BookingLinkScreen>(),
    );

    final Map<String, bool> hubs = <String, bool>{
      RouteNames.masterMenu: true,
      RouteNames.ownerSettings: false,
      RouteNames.adminSettings: false,
      RouteNames.salonMasterSettings: false,
    };
    hubs.forEach((String location, bool show) {
      final Widget hub = _leafWidget(router, context, location);
      expect(hub, isA<SettingsHubScreen>(), reason: location);
      expect(
        (hub as SettingsHubScreen).showBookingLinks,
        show,
        reason: '$location showBookingLinks',
      );
    });
  });
}
