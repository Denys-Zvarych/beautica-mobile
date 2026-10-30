// Phase 426 — `/settings/blocked-clients` route: role gate + registration.
//
//   • auth gate (pure seam `authRedirectForLocation`): INDEPENDENT_MASTER,
//     SALON_OWNER, SALON_ADMIN admitted; SALON_MASTER / CLIENT bounced to
//     roleHomePath; signed out → login.
//   • the PRODUCTION router resolves the literal to BlockedClientsScreen
//     (D4: no dynamic sibling shadows it) and leaves `/settings` alone.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/moderation/presentation/blocked_clients_screen.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
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
  group('auth gate on ${RouteNames.blockedClients}', () {
    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      test('${role.name} is ADMITTED', () {
        expect(
          authRedirectForLocation(_sessionFor(role), RouteNames.blockedClients),
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
          authRedirectForLocation(_sessionFor(role), RouteNames.blockedClients),
          roleHomePath(role),
        );
      });
    }

    test('signed out is sent to login', () {
      expect(
        authRedirectForLocation(
          const AsyncData<AuthSession>(AuthSession.unauthenticated()),
          RouteNames.blockedClients,
        ),
        RouteNames.login,
      );
    });

    test('the gate does not touch the plain ${RouteNames.settings} route', () {
      expect(
        authRedirectForLocation(
          _sessionFor(UserRole.client),
          RouteNames.settings,
        ),
        isNull,
      );
    });
  });

  testWidgets('production router: literal resolves to BlockedClientsScreen; '
      '${RouteNames.settings} still builds SettingsScreen', (tester) async {
    final GoRouter router = _productionRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(const SizedBox(key: Key('ctx')));
    final BuildContext context = tester.element(find.byKey(const Key('ctx')));

    expect(
      _leafWidget(router, context, RouteNames.blockedClients),
      isA<BlockedClientsScreen>(),
    );
    expect(
      _leafWidget(router, context, RouteNames.settings),
      isA<SettingsScreen>(),
    );
  });
}
