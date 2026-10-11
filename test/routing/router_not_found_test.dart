// Phase 380 — router-level not-found handling.
//
// `appRouter` registers an `onException` that sends a location NO route
// matches to the viewer's own home ([roleHomePath]) — or to the splash, where
// [authRedirect] decides, when the session is not an authenticated one —
// instead of go_router's default, unbranded "Page Not Found" page. This file
// drives the REAL `appRouterProvider` (go_router's own matcher + the real
// `authRedirect`) and asserts on the location that settles and on the absence
// of go_router's default error page.
//
// It also pins [isNoRouteMatch] against go_router's own no-match exception:
// go_router exposes no type/code for it, only a message, so a go_router
// upgrade that rewords it turns the first test red rather than silently
// routing every no-match to the "keep current page" arm.
//
// Layer: Widget (real appRouterProvider + authRedirect, faked providers).

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/route_pump.dart';
import '../helpers/test_container.dart';

const String _kUnknownLocation = '/definitely/not/a/route';

/// A reachable, NON-home location per role to start each no-match test from.
const Map<UserRole, String> _offHome = <UserRole, String>{
  UserRole.salonOwner: RouteNames.mySalons,
  UserRole.independentMaster: RouteNames.services,
};

class _Auth extends AuthNotifier {
  /// `null` = a settled UNAUTHENTICATED session.
  static UserRole? role = UserRole.salonOwner;

  @override
  Future<AuthSession> build() async {
    final UserRole? r = role;
    if (r == null) return const AuthSession.unauthenticated();
    return AuthSession.authenticated(
      user: User(
        id: 'user-1',
        email: 'user@beautica.test',
        role: r,
        firstName: 'Олена',
        lastName: 'Ковальчук',
        hasMasterProfile: true,
      ),
      accessToken: 'token',
    );
  }
}

class _Profile extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'master-1',
    firstName: 'Олена',
    lastName: 'Ковальчук',
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

class _MySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: 'salon-1', name: 'Test Salon', isPrimary: true),
  ];
}

class _MockDio extends Mock implements Dio {}

class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  setUp(() {
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    _Auth.role = UserRole.salonOwner;
  });
  tearDown(AppStartTime.resetForTest);

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final _MockDio dio = _MockDio();
    when(() => dio.get<Object?>(any())).thenAnswer(
      (invocation) async => Response<Object?>(
        requestOptions: RequestOptions(
          path: invocation.positionalArguments[0] as String,
        ),
        statusCode: 200,
        data: <String, Object?>{'success': true, 'data': <Object?>[]},
      ),
    );
    final ProviderContainer container = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        authProvider.overrideWith(_Auth.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        mySalonsProvider.overrideWith(_MySalons.new),
        masterProfileProvider.overrideWith(_Profile.new),
        dioProvider.overrideWithValue(dio),
      ],
    );
    final GoRouter router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _RouterApp(router: router),
      ),
    );
    await container.read(authProvider.future);
    await tester.pump();
    return router;
  }

  /// The location the router settled on. A no-match leaves `router.state`
  /// throwing, so the raw configuration is read instead.
  String settledPath(GoRouter router) =>
      // router-location-ok: asserting the post-exception landing.
      router.routerDelegate.currentConfiguration.uri.path;

  /// Parks the router on [path] — a location that is NOT the expected
  /// landing. `onException` returns the CURRENT configuration when it does
  /// nothing, so a test that starts ON the role home (where boot leaves it)
  /// passes identically with the redirect deleted (mutation-probed
  /// 2026-10-06: 3 of 4 no-match tests stayed green that way).
  Future<void> startAt(
    WidgetTester tester,
    GoRouter router,
    String path,
  ) async {
    router.go(path);
    await pumpUntil(tester, () => settledPath(router) == path);
    expect(settledPath(router), path);
  }

  testWidgets('isNoRouteMatch recognises go_router\'s OWN no-match exception '
      '(pins the message against a go_router upgrade)', (tester) async {
    final GoRouter router = await pumpRouter(tester);

    final GoException? error = router.configuration
        .findMatch(Uri.parse(_kUnknownLocation))
        .error;

    expect(error, isNotNull);
    expect(isNoRouteMatch(error!), isTrue);
    expect(isNoRouteMatch(GoException('redirect loop detected')), isFalse);
  });

  final Map<UserRole, String> homes = <UserRole, String>{
    UserRole.salonOwner: roleHomePath(UserRole.salonOwner),
    UserRole.independentMaster: roleHomePath(UserRole.independentMaster),
  };
  for (final MapEntry<UserRole, String> entry in homes.entries) {
    testWidgets('an UNKNOWN path sends a ${entry.key.name} to its role home — '
        'never go_router\'s default "Page Not Found"', (tester) async {
      _Auth.role = entry.key;
      final GoRouter router = await pumpRouter(tester);
      await startAt(tester, router, _offHome[entry.key]!);

      router.go(_kUnknownLocation);
      await pumpUntil(tester, () => settledPath(router) == entry.value);

      expect(settledPath(router), entry.value);
      expect(router.routerDelegate.currentConfiguration.error, isNull);
      expect(find.text('Page Not Found'), findsNothing);
    });
  }

  // Outcome pin only: the top-level [authRedirect] already sends a logged-out
  // viewer to /login before `onException`'s splash arm matters — deleting
  // that arm's `router.go` leaves this green (mutation-probed 2026-10-06).
  testWidgets('an UNKNOWN path while logged out lands on /login, never '
      'go_router\'s default "Page Not Found"', (tester) async {
    _Auth.role = null;
    final GoRouter router = await pumpRouter(tester);
    await startAt(tester, router, RouteNames.forgotPassword);

    router.go(_kUnknownLocation);
    await pumpUntil(tester, () => settledPath(router) == RouteNames.login);

    expect(settledPath(router), RouteNames.login);
    expect(find.text('Page Not Found'), findsNothing);
  });

  testWidgets('the EMPTY-id root `/services//edit` (formerly a dead redirect '
      'branch) is a no-match -> INDEPENDENT_MASTER role home', (tester) async {
    _Auth.role = UserRole.independentMaster;
    final GoRouter router = await pumpRouter(tester);
    await startAt(tester, router, RouteNames.services);

    router.go('${RouteNames.services}//edit');
    await pumpUntil(
      tester,
      () => settledPath(router) == roleHomePath(UserRole.independentMaster),
    );

    expect(settledPath(router), roleHomePath(UserRole.independentMaster));
    expect(find.byType(ServiceEditScreen), findsNothing);
    expect(find.text('Page Not Found'), findsNothing);
  });

  // The OTHER half of `onException`: any GoException that is NOT a no-match
  // (redirect loop / limit, a throwing redirect) is logged and the current
  // page is KEPT — forwarding it home could re-enter the same loop forever.
  // No real route throws or loops, so the router's own parser handler (the
  // closure go_router wraps `onException` in) is invoked directly with such
  // an error. Starts OFF the role home so "kept" and "sent home" differ.
  testWidgets('a NON-no-match GoException (redirect loop) keeps the current '
      'page — it is NOT forwarded to the role home', (tester) async {
    final GoRouter router = await pumpRouter(tester);
    router.go(RouteNames.mySalons);
    await pumpUntil(tester, () => settledPath(router) == RouteNames.mySalons);
    expect(RouteNames.mySalons, isNot(roleHomePath(UserRole.salonOwner)));

    router.routeInformationParser.onParserException!(
      router.routerDelegate.navigatorKey.currentContext!,
      RouteMatchList(
        matches: const <RouteMatchBase>[],
        uri: Uri.parse('/loop'),
        pathParameters: const <String, String>{},
        error: GoException('redirect loop detected /a => /b => /a'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(settledPath(router), RouteNames.mySalons);
  });
}
