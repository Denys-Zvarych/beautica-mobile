// M509 — the «Клієнти» routes: registration, literal-before-dynamic ordering
// and the per-role fences.
//
//   /master/clients          INDEPENDENT_MASTER   (`/master/*` prefix gate)
//   /staff/clients           SALON_MASTER         (`/staff/*` prefix gate)
//   /owner/master/clients    SALON_OWNER          (`/owner/master/*` prefix gate)
//   <each>/user/:userId, <each>/guest/:bookingId  the M510 card and
//   <each>/user/:userId/rating, plus the salon-scoped pair /salons/:salonId/clients/{user,guest}/:id
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
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/domain/walk_in_launch.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_route.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:flutter/material.dart';
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
      // M510 — «Рейтинг клієнта» below every card route.
      '${RouteNames.masterClients}/user/u1/rating',
      '${RouteNames.masterClients}/guest/b1/rating',
      '${RouteNames.salonMasterClients}/user/u1/rating',
      '${RouteNames.salonMasterClients}/guest/b1/rating',
      '${RouteNames.salonClients('s1')}/user/u1/rating',
      '${RouteNames.salonClients('s1')}/guest/b1/rating?masterId=m1',
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
        '${RouteNames.masterClients}/user/u1/rating',
        '${RouteNames.salonClients('s1')}/guest/b1/rating',
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

  group('clientRatingRoute', () {
    test('below the card, same ?masterId= rule, ids URL-encoded', () {
      expect(
        clientRatingRoute(
          RouteNames.masterClients,
          const ClientRef.registered('u1'),
        ),
        '/master/clients/user/u1/rating',
      );
      expect(
        clientRatingRoute(
          RouteNames.salonClients('s1'),
          const ClientRef.guest('b1'),
          masterId: 'm-7',
        ),
        '/salons/s1/clients/guest/b1/rating?masterId=m-7',
      );
      expect(
        clientRatingRoute(
          RouteNames.masterClients,
          const ClientRef.guest('a/b'),
        ),
        '/master/clients/guest/a%2Fb/rating',
      );
    });
  });

  group(
    'salon card route: ?masterId= (M509 audit carry-over; owner + admin, CLI-74)',
    () {
      const String uuid = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

      Future<ClientListScope> scopeFor(
        WidgetTester tester,
        UserRole role,
        String location,
      ) async {
        final ProviderContainer container = makeTestContainer(
          overrides: <Object>[
            authProvider.overrideWith(
              () => _FixedAuth(
                AuthSession.authenticated(
                  user: User(
                    id: 'u1',
                    email: 'a@b.c',
                    role: role,
                    salonId: 's-1',
                  ),
                  accessToken: 't',
                ),
              ),
            ),
            authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
            secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          ],
        );
        await container.read(authProvider.future);
        final GoRouter router = container.read(appRouterProvider);
        addTearDown(router.dispose);
        await tester.pumpWidget(const SizedBox(key: Key('ctx')));
        final BuildContext context = tester.element(
          find.byKey(const Key('ctx')),
        );
        final RouteMatchList match = router.configuration.findMatch(
          Uri.parse(location),
        );
        expect(match.isError, isFalse, reason: location);
        final Widget w = match.last.route.builder!(
          context,
          router.configuration.buildTopLevelGoRouterState(match),
        );
        return (w as ClientCardScreen).scope;
      }

      testWidgets('owner + a UUID → narrowed to the owner\'s master row', (
        tester,
      ) async {
        final ClientListScope scope = await scopeFor(
          tester,
          UserRole.salonOwner,
          '/salons/s-1/clients/user/u-1?masterId=$uuid',
        );
        expect(
          scope,
          const ClientListScope.salon(salonId: 's-1', masterId: uuid),
        );
      });

      testWidgets('owner + a non-UUID masterId is ignored', (tester) async {
        for (final String bad in <String>[
          'm-7',
          '..%2F..%2Fx',
          '$uuid%0Ax',
          'x$uuid',
          '',
        ]) {
          final ClientListScope scope = await scopeFor(
            tester,
            UserRole.salonOwner,
            '/salons/s-1/clients/user/u-1?masterId=$bad',
          );
          expect(
            scope,
            const ClientListScope.salon(salonId: 's-1'),
            reason: 'masterId=$bad',
          );
        }
      });

      testWidgets(
        'admin + a UUID → honoured (master chips, CLI-74 / CLI-D12)',
        (tester) async {
          final ClientListScope scope = await scopeFor(
            tester,
            UserRole.salonAdmin,
            '/salons/s-1/clients/guest/b-1?masterId=$uuid',
          );
          expect(
            scope,
            const ClientListScope.salon(salonId: 's-1', masterId: uuid),
          );
        },
      );

      testWidgets('any other role + a UUID is ignored', (tester) async {
        for (final UserRole role in <UserRole>[
          UserRole.salonMaster,
          UserRole.independentMaster,
          UserRole.client,
        ]) {
          final ClientListScope scope = await scopeFor(
            tester,
            role,
            '/salons/s-1/clients/user/u-1?masterId=$uuid',
          );
          expect(
            scope,
            const ClientListScope.salon(salonId: 's-1'),
            reason: '$role',
          );
        }
      });

      testWidgets('no query → the whole-salon scope', (tester) async {
        final ClientListScope scope = await scopeFor(
          tester,
          UserRole.salonOwner,
          '/salons/s-1/clients/user/u-1',
        );
        expect(scope, const ClientListScope.salon(salonId: 's-1'));
      });
    },
  );

  // M543 (CLI-80, D2/D3/D6) — the card's «Записати» binding and the walk-in
  // routes' typed `extra`.
  group('M543 book from the client card', () {
    const ClientPrefill prefill = ClientPrefill(
      firstName: 'Оксана',
      lastName: 'Мельник',
      phone: '+380671234567',
    );

    Future<GoRouter> prodRouter(UserRole role) async {
      final ProviderContainer container = makeTestContainer(
        overrides: <Object>[
          authProvider.overrideWith(
            () => _FixedAuth(
              AuthSession.authenticated(
                user: User(
                  id: 'u1',
                  email: 'a@b.c',
                  role: role,
                  salonId: 's-1',
                ),
                accessToken: 't',
              ),
            ),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        ],
      );
      await container.read(authProvider.future);
      final GoRouter router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      return router;
    }

    Future<BuildContext> ctx(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox(key: Key('ctx')));
      return tester.element(find.byKey(const Key('ctx')));
    }

    GoRouterState stateOf(GoRouter router, String location, Object? extra) {
      final RouteMatchList match = router.configuration.findMatch(
        Uri.parse(location),
        extra: extra,
      );
      expect(match.isError, isFalse, reason: location);
      return router.configuration.buildTopLevelGoRouterState(match);
    }

    GoRoute leaf(GoRouter router, String location) =>
        router.configuration.findMatch(Uri.parse(location)).last.route;

    Future<ClientCardScreen> cardAt(
      WidgetTester tester,
      UserRole role,
      String location,
    ) async {
      final GoRouter router = await prodRouter(role);
      final BuildContext context = await ctx(tester);
      return leaf(router, location).builder!(
            context,
            stateOf(router, location, null),
          )
          as ClientCardScreen;
    }

    for (final (UserRole role, String location) in <(UserRole, String)>[
      (UserRole.independentMaster, '/master/clients/user/u-1'),
      (UserRole.independentMaster, '/master/clients/guest/b-1'),
      (UserRole.salonOwner, '/salons/s-1/clients/user/u-1'),
      (UserRole.salonOwner, '/salons/s-1/clients/guest/b-1'),
      (UserRole.salonAdmin, '/salons/s-1/clients/user/u-1'),
    ]) {
      testWidgets('$role: $location binds «Записати»', (tester) async {
        final ClientCardScreen card = await cardAt(tester, role, location);
        expect(card.onBookClient, isNotNull);
      });
    }

    for (final String location in <String>[
      '/staff/clients/user/u-1',
      '/staff/clients/guest/b-1',
    ]) {
      testWidgets('SALON_MASTER: $location has no «Записати»', (tester) async {
        final ClientCardScreen card = await cardAt(
          tester,
          UserRole.salonMaster,
          location,
        );
        expect(card.onBookClient, isNull);
      });
    }

    testWidgets('SALON_MASTER on a salon card route → still no launcher '
        '(canPickClients double gate)', (tester) async {
      final ClientCardScreen card = await cardAt(
        tester,
        UserRole.salonMaster,
        '/salons/s-1/clients/user/u-1',
      );
      expect(card.onBookClient, isNull);
    });

    /// Runs [card]'s launcher inside a recording router; returns the pushed
    /// location and extra.
    Future<(String, Object?)> launch(
      WidgetTester tester,
      ClientCardScreen card, {
      ClientPrefill launched = prefill,
      bool popAfter = false,
    }) async {
      final List<(String, Object?)> pushed = <(String, Object?)>[];
      Widget record(BuildContext _, GoRouterState state) {
        pushed.add((state.uri.toString(), state.extra));
        return const SizedBox();
      }

      final GoRouter recorder = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, _) => Builder(
              builder: (BuildContext context) => TextButton(
                key: const Key('go'),
                onPressed: () => card.onBookClient?.call(context, launched),
                child: const Text('go'),
              ),
            ),
          ),
          GoRoute(path: RouteNames.masterBookingNew, builder: record),
          GoRoute(path: RouteNames.masterBookingNewServices, builder: record),
          GoRoute(path: RouteNames.salonStaffBookingNew, builder: record),
        ],
      );
      addTearDown(recorder.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: recorder));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      if (popAfter) {
        // BOOK-80 — back from the first pushed step returns to the card.
        recorder.pop();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('go')), findsOneWidget);
        expect(recorder.state.uri.toString(), '/');
      }
      return pushed.single;
    }

    // BOOK-80 / CLI-80 (user 2026-11-26) — a COMPLETE prefill skips the
    // client step: the service step is pushed straight from the card.
    for (final String cardLocation in <String>[
      '/master/clients/user/u-1',
      '/master/clients/guest/b-1',
    ]) {
      testWidgets('IM $cardLocation, complete prefill → the service step with '
          'a WalkInGuest, no PII in the location, back → the card', (
        tester,
      ) async {
        final ClientCardScreen card = await cardAt(
          tester,
          UserRole.independentMaster,
          cardLocation,
        );
        const ClientPrefill withPhoto = ClientPrefill(
          firstName: ' Оксана ',
          lastName: 'Мельник',
          phone: '+380671234567',
          avatarUrl: 'https://cdn.example/a.jpg',
          rating: 4.5,
          ratingCount: 3,
        );
        final (String location, Object? extra) = await launch(
          tester,
          card,
          launched: withPhoto,
          popAfter: true,
        );
        expect(location, RouteNames.masterBookingNewServices);
        expect(extra, isA<WalkInGuest>());
        final WalkInGuest g = extra! as WalkInGuest;
        expect(g.name, 'Оксана');
        expect(g.surname, 'Мельник');
        expect(g.phone, '+380671234567');
        // BOOK-81 — the card's photo + ★ carry onto the review strip.
        expect(g.avatarUrl, 'https://cdn.example/a.jpg');
        expect(g.rating, 4.5);
        expect(g.ratingCount, 3);
        expect(g.toString(), 'WalkInGuest()');
      });
    }

    // Incomplete prefill (CLI-E10 no phone, one name part, legacy
    // display-name fallback, non-UA phone) → the client step, as before.
    for (final (String label, ClientPrefill incomplete)
        in <(String, ClientPrefill)>[
          (
            'no phone (CLI-E10)',
            const ClientPrefill(firstName: 'Оксана', lastName: 'Мельник'),
          ),
          (
            'first name only (legacy display-name fallback)',
            const ClientPrefill(firstName: 'Оксана', phone: '+380671234567'),
          ),
          (
            'surname only',
            const ClientPrefill(lastName: 'Мельник', phone: '+380671234567'),
          ),
          (
            'blank surname',
            const ClientPrefill(
              firstName: 'Оксана',
              lastName: '  ',
              phone: '+380671234567',
            ),
          ),
          (
            'non-UA phone',
            const ClientPrefill(
              firstName: 'Оксана',
              lastName: 'Мельник',
              phone: '+48601234567',
            ),
          ),
        ]) {
      testWidgets('IM card, $label → /master/bookings/new with the '
          'WalkInLaunch, back → the card', (tester) async {
        final ClientCardScreen card = await cardAt(
          tester,
          UserRole.independentMaster,
          '/master/clients/user/u-1',
        );
        final (String location, Object? extra) = await launch(
          tester,
          card,
          launched: incomplete,
          popAfter: true,
        );
        expect(location, RouteNames.masterBookingNew);
        expect(extra, isA<WalkInLaunch>());
        final WalkInLaunch l = extra! as WalkInLaunch;
        expect(l.prefill, incomplete);
        expect(l.salonId, isNull);
        expect(l.toString(), 'WalkInLaunch()');
      });
    }

    testWidgets('/master/bookings/new/services: a WalkInGuest extra '
        'satisfies the redirect; none bounces to /master/bookings/new', (
      tester,
    ) async {
      final GoRouter router = await prodRouter(UserRole.independentMaster);
      final BuildContext context = await ctx(tester);
      const WalkInGuest guest = WalkInGuest(
        name: 'Оксана',
        surname: 'Мельник',
        phone: '+380671234567',
      );
      final GoRoute services = leaf(
        router,
        RouteNames.masterBookingNewServices,
      );
      expect(
        services.redirect!(
          context,
          stateOf(router, RouteNames.masterBookingNewServices, guest),
        ),
        isNull,
      );
      expect(
        services.redirect!(
          context,
          stateOf(router, RouteNames.masterBookingNewServices, null),
        ),
        RouteNames.masterBookingNew,
      );
    });

    testWidgets('salon card → /salon/bookings/new with WalkInLaunch(salonId)', (
      tester,
    ) async {
      final ClientCardScreen card = await cardAt(
        tester,
        UserRole.salonOwner,
        '/salons/s-1/clients/guest/b-1?masterId=a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
      );
      final (String location, Object? extra) = await launch(tester, card);
      expect(location, RouteNames.salonStaffBookingNew);
      final WalkInLaunch l = extra! as WalkInLaunch;
      expect(l.salonId, 's-1');
      expect(l.prefill, prefill);
    });

    testWidgets('/master/bookings/new: WalkInLaunch → initialPrefill; none '
        '→ null', (tester) async {
      final GoRouter router = await prodRouter(UserRole.independentMaster);
      final BuildContext context = await ctx(tester);
      for (final (Object? extra, ClientPrefill? expected)
          in <(Object?, ClientPrefill?)>[
            (const WalkInLaunch(prefill: prefill), prefill),
            (null, null),
            ('junk', null),
          ]) {
        final Page<dynamic> page =
            leaf(router, RouteNames.masterBookingNew).pageBuilder!(
              context,
              stateOf(router, RouteNames.masterBookingNew, extra),
            );
        final WalkInGuestStepScreen screen =
            (page as MaterialPage<void>).child as WalkInGuestStepScreen;
        expect(screen.initialPrefill, expected, reason: '$extra');
      }
    });

    testWidgets('/salon/bookings/new accepts String and WalkInLaunch; '
        'redirects on a missing salonId', (tester) async {
      final GoRouter router = await prodRouter(UserRole.salonOwner);
      final BuildContext context = await ctx(tester);
      final GoRoute route = leaf(router, RouteNames.salonStaffBookingNew);

      for (final Object? bad in <Object?>[
        null,
        '',
        const WalkInLaunch(prefill: prefill),
        const WalkInLaunch(prefill: prefill, salonId: ''),
      ]) {
        expect(
          await route.redirect!(
            context,
            stateOf(router, RouteNames.salonStaffBookingNew, bad),
          ),
          isNotNull,
          reason: '$bad',
        );
      }

      for (final (Object extra, ClientPrefill? expected)
          in <(Object, ClientPrefill?)>[
            ('s-1', null),
            (const WalkInLaunch(prefill: prefill, salonId: 's-1'), prefill),
          ]) {
        final GoRouterState state = stateOf(
          router,
          RouteNames.salonStaffBookingNew,
          extra,
        );
        expect(await route.redirect!(context, state), isNull);
        final Page<dynamic> page = route.pageBuilder!(context, state);
        final SalonCreateBookingScreen screen =
            (page as MaterialPage<void>).child as SalonCreateBookingScreen;
        expect(screen.salonId, 's-1');
        expect(screen.initialPrefill, expected);
      }
    });
  });
}
