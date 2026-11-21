// M509 — the «Клієнти» routes: registration, literal-before-dynamic ordering
// and the per-role fences.
//
//   /master/clients          INDEPENDENT_MASTER   (`/master/*` prefix gate)
//   /staff/clients           SALON_MASTER         (`/staff/*` prefix gate)
//   /owner/master/clients    SALON_OWNER          (`/owner/master/*` prefix gate)
//   <each>/user/:userId, <each>/guest/:bookingId  the M510 card (placeholder
//   until M510), plus the salon-scoped pair /salons/:salonId/clients/{user,guest}/:id
//
// No new role rule was added — each tab rides the gate of its sibling tabs —
// so the matrix below is what pins "same redirect rules as the sibling tabs".
// The pure `authRedirectForLocation` seam is used for the gates (it needs no
// providers); `findMatch` on the PRODUCTION router proves registration.

import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_route.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

class _FixedAuth extends AuthNotifier {
  _FixedAuth(this._session);
  final AuthSession _session;
  @override
  Future<AuthSession> build() async => _session;
}

AsyncValue<AuthSession> _session(UserRole role) => AsyncData<AuthSession>(
  AuthSession.authenticated(
    user: User(id: 'u-$role', email: 'a@b.c', role: role, salonId: 's1'),
    accessToken: 'tkn',
  ),
);

GoRouter _productionRouter() {
  final ProviderContainer container = makeTestContainer(
    overrides: <Object>[
      authProvider.overrideWith(
        () => _FixedAuth(
          const AuthSession.authenticated(
            user: User(
              id: 'u1',
              email: 'a@b.c',
              role: UserRole.independentMaster,
            ),
            accessToken: 't',
          ),
        ),
      ),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  return container.read(appRouterProvider);
}

void main() {
  group('registration (production router)', () {
    final List<String> locations = <String>[
      RouteNames.masterClients,
      RouteNames.salonMasterClients,
      RouteNames.ownerMasterClients,
      '${RouteNames.masterClients}/user/u1',
      '${RouteNames.masterClients}/guest/b1',
      '${RouteNames.salonMasterClients}/user/u1',
      '${RouteNames.salonMasterClients}/guest/b1',
      '${RouteNames.salonClients('s1')}/user/u1',
      '${RouteNames.salonClients('s1')}/guest/b1',
      '${RouteNames.salonClients('s1')}/user/u1?masterId=m1',
    ];

    test('every list route and every card route resolves to a GoRoute', () {
      final GoRouter router = _productionRouter();
      final List<String> unresolved = <String>[
        for (final String l in locations)
          if (router.configuration.findMatch(Uri.parse(l)).isError) l,
      ];
      expect(unresolved, isEmpty);
    });

    test('a card route resolves to the CARD leaf, never to the list route '
        '(literal user/guest segments, no shadowing)', () {
      final GoRouter router = _productionRouter();
      for (final String card in <String>[
        '${RouteNames.masterClients}/user/u1',
        '${RouteNames.masterClients}/guest/b1',
        '${RouteNames.salonMasterClients}/user/u1',
        '${RouteNames.salonClients('s1')}/guest/b1',
      ]) {
        final RouteMatchList match = router.configuration.findMatch(
          Uri.parse(card),
        );
        expect(
          match.fullPath,
          isNot(anyOf(RouteNames.masterClients, RouteNames.salonMasterClients)),
          reason: card,
        );
        expect(
          match.fullPath,
          contains(':'),
          reason: '$card → ${match.fullPath}',
        );
      }
    });

    test('an unknown tail under a list route is NOT a route', () {
      final GoRouter router = _productionRouter();
      expect(
        router.configuration
            .findMatch(Uri.parse('${RouteNames.masterClients}/nothing'))
            .isError,
        isTrue,
      );
    });
  });

  group('role fences (same rules as the sibling tabs)', () {
    String? redirect(UserRole role, String location) =>
        authRedirectForLocation(_session(role), location);

    test('INDEPENDENT_MASTER: /master/clients admitted; /staff and '
        '/owner/master fenced off', () {
      expect(
        redirect(UserRole.independentMaster, RouteNames.masterClients),
        isNull,
      );
      expect(
        redirect(
          UserRole.independentMaster,
          '${RouteNames.masterClients}/user/u1',
        ),
        isNull,
      );
      expect(
        redirect(UserRole.independentMaster, RouteNames.salonMasterClients),
        isNotNull,
      );
      expect(
        redirect(UserRole.independentMaster, RouteNames.ownerMasterClients),
        isNotNull,
      );
    });

    test('SALON_MASTER: /staff/clients admitted; /master/clients and '
        '/owner/master/clients fenced off', () {
      expect(
        redirect(UserRole.salonMaster, RouteNames.salonMasterClients),
        isNull,
      );
      expect(
        redirect(
          UserRole.salonMaster,
          '${RouteNames.salonMasterClients}/guest/b1',
        ),
        isNull,
      );
      expect(
        redirect(UserRole.salonMaster, RouteNames.masterClients),
        isNotNull,
      );
      expect(
        redirect(UserRole.salonMaster, RouteNames.ownerMasterClients),
        isNotNull,
      );
    });

    test('SALON_OWNER: /owner/master/clients admitted; the other two fenced '
        'off', () {
      expect(
        redirect(UserRole.salonOwner, RouteNames.ownerMasterClients),
        isNull,
      );
      expect(
        redirect(UserRole.salonOwner, RouteNames.masterClients),
        isNotNull,
      );
      expect(
        redirect(UserRole.salonOwner, RouteNames.salonMasterClients),
        isNotNull,
      );
    });

    test('SALON_ADMIN has no master-mode list: all three fenced off', () {
      for (final String path in <String>[
        RouteNames.masterClients,
        RouteNames.salonMasterClients,
        RouteNames.ownerMasterClients,
      ]) {
        expect(redirect(UserRole.salonAdmin, path), isNotNull, reason: path);
      }
    });

    test('CLIENT is fenced off every «Клієнти» surface (CLI-07 untouched)', () {
      for (final String path in <String>[
        RouteNames.masterClients,
        RouteNames.salonMasterClients,
        RouteNames.ownerMasterClients,
      ]) {
        expect(redirect(UserRole.client, path), isNotNull, reason: path);
      }
    });

    test('unauthenticated users go to /login', () {
      for (final String path in <String>[
        RouteNames.masterClients,
        RouteNames.salonMasterClients,
        RouteNames.ownerMasterClients,
      ]) {
        expect(
          authRedirectForLocation(
            const AsyncData<AuthSession>(AuthSession.unauthenticated()),
            path,
          ),
          RouteNames.login,
          reason: path,
        );
      }
    });
  });

  group('clientCardRoute', () {
    test('registered → user, guest → guest, below the host list route', () {
      expect(
        clientCardRoute(
          RouteNames.masterClients,
          const ClientRef.registered('u1'),
        ),
        '/master/clients/user/u1',
      );
      expect(
        clientCardRoute(
          RouteNames.salonMasterClients,
          const ClientRef.guest('b1'),
        ),
        '/staff/clients/guest/b1',
      );
      expect(
        clientCardRoute(
          RouteNames.salonClients('s1'),
          const ClientRef.guest('b1'),
        ),
        '/salons/s1/clients/guest/b1',
      );
    });

    test('owner master mode appends ?masterId=, ids are URL-encoded', () {
      expect(
        clientCardRoute(
          RouteNames.salonClients('s1'),
          const ClientRef.registered('u1'),
          masterId: 'm-7',
        ),
        '/salons/s1/clients/user/u1?masterId=m-7',
      );
      expect(
        clientCardRoute(RouteNames.masterClients, const ClientRef.guest('a/b')),
        '/master/clients/guest/a%2Fb',
      );
    });
  });
}
