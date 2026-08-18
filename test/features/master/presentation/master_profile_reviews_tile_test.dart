// Phase 4.6 — Entry-point test: the master profile's «Відгуки» stat tile
// (`Key('master-profile-reviews-tile')`) is present and tapping it PUSHES the
// received-reviews route (`/master/received-reviews`).
//
// The tap uses the production `context.push(...)` inside the profile screen —
// this test deliberately does NOT drive navigation via `router.go`, which would
// yield a declarative match and false-pass the app's pushed-leaf nav detection
// (see MEMORY: "go_router push excludes fullPath"). We assert the pushed
// destination actually mounts on top of the profile.
//
// Strategy mirrors profile_to_services_navigation_test.dart: stub the auth +
// master-profile providers, mock the repositories, and host both routes on a
// real GoRouter whose received-reviews route renders a keyed sentinel (the real
// reviews screen is exercised end-to-end by the widget + integration tests).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

const _fakeUser = User(
  id: 'user-master-1',
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const _stubMaster = Master(
  id: 'user-master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 5,
  type: MasterType.independentMaster,
);

class _StubMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() {
    // ignore: unawaited_futures — post the resolved state asynchronously while
    // keeping the Future<Master> return type.
    Future<void>.microtask(() => state = const AsyncData<Master>(_stubMaster));
    return Completer<Master>().future;
  }
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _fakeUser, accessToken: 'token');
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterProfile,
  redirect: (BuildContext context, GoRouterState state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (BuildContext context, GoRouterState state) =>
          const MasterProfileScreen(),
    ),
    GoRoute(
      path: RouteNames.masterReceivedReviews,
      builder: (BuildContext context, GoRouterState state) => const Scaffold(
        key: Key('reviews-destination'),
        body: SizedBox.shrink(),
      ),
    ),
  ],
);

ProviderScope _buildApp({
  required _MockMasterRepository masterRepo,
  required _MockServiceRepository serviceRepo,
  required GoRouter router,
}) {
  return ProviderScope(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(_StubAuthNotifier.new),
      masterProfileProvider.overrideWith(() => _StubMasterProfileNotifier()),
      masterRepositoryProvider.overrideWithValue(masterRepo),
      serviceRepositoryProvider.overrideWithValue(serviceRepo),
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
    ),
  );
}

void main() {
  late _MockMasterRepository masterRepo;
  late _MockServiceRepository serviceRepo;

  setUp(() {
    masterRepo = _MockMasterRepository();
    serviceRepo = _MockServiceRepository();
    when(
      () => serviceRepo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[]);
  });

  testWidgets('the reviews stat tile is present and tapping it pushes '
      '/master/received-reviews', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GoRouter router = _buildRouter();
    await tester.pumpWidget(
      _buildApp(
        masterRepo: masterRepo,
        serviceRepo: serviceRepo,
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    final Finder tile = find.byKey(const Key('master-profile-reviews-tile'));
    expect(tile, findsOneWidget, reason: 'the reviews stat tile must render');
    // The destination is not yet mounted before the tap.
    expect(find.byKey(const Key('reviews-destination')), findsNothing);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    // The pushed received-reviews route is now on top of the profile.
    expect(
      find.byKey(const Key('reviews-destination')),
      findsOneWidget,
      reason:
          'tapping the reviews tile must context.push the received-reviews '
          'route onto the stack',
    );
  });
}
