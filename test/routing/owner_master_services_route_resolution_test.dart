// Phase 380 (24.1c) — pins the RESOLVED screen TYPE for the owner master-mode
// services drill-ins, and that both resolve INSIDE the owner shell's
// `SalonMasterTarget` scope.
//
// `app_router.dart` registers, as siblings under the `/owner/master/*`
// ShellRoute:
//   • `/owner/master/services/setup`             (literal)
//   • `/owner/master/services/:serviceId/edit`   (dynamic)
//
// They differ in segment count (4 vs 5), so they CANNOT shadow each other in
// either registration order — this file makes NO ordering claim (swapping the
// two registrations stays green, by construction). What it pins is
// RESOLUTION: it runs go_router's OWN matcher (real `appRouterProvider`,
// `router.go`) and asserts on the widget TYPE that mounts and the
// `serviceTargetProvider` scope it reads — a path assertion passes while the
// wrong screen renders.
//
// The scope assertions are the other half: a setup POST or an edit
// PUT/DELETE read outside the shell's override would hit the
// INDEPENDENT_MASTER `/masters/me/services` endpoints with the owner's token.
//
// Layer: Widget (real appRouterProvider + authRedirect, faked providers).

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
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
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_target.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
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

const String _kOwnerUserId = 'user-owner-U';
const String _kOwnerMasterRowId = 'master-row-owner-M';
const String _kSalonId = 'salon-owner-S';

const ServiceTarget _kOwnerTarget = ServiceTarget.salonMaster(
  salonId: _kSalonId,
  masterId: _kOwnerMasterRowId,
);

class _OwnerAuth extends AuthNotifier {
  static UserRole role = UserRole.salonOwner;

  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: User(
      id: _kOwnerUserId,
      email: 'owner@beautica.test',
      role: role,
      firstName: 'Олена',
      lastName: 'Ковальчук',
      hasMasterProfile: true,
    ),
    accessToken: 'token',
  );
}

class _OwnerMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: _kOwnerMasterRowId,
    firstName: 'Олена',
    lastName: 'Ковальчук',
    reviewCount: 0,
    type: MasterType.salonOwner,
    salonId: _kSalonId,
  );
}

class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: _kSalonId, name: 'Test Salon', isPrimary: true),
  ];
}

/// `mySalonsProvider` held unresolved until the test completes [gate] — the
/// cold-deep-link window where `canManageSalonProvider` is fail-closed.
class _GatedMySalons extends MySalons {
  static Completer<List<Salon>> gate = Completer<List<Salon>>();

  @override
  Future<List<Salon>> build() => gate.future;
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

/// The owner's OWN catalogue row as `GET /salons/S/masters/M/services`
/// returns it (phase 380 security cases).
Map<String, Object?> _ownRow(String assignmentId, String defId) =>
    <String, Object?>{
      'id': assignmentId,
      'masterId': _kOwnerMasterRowId,
      'serviceDefinition': <String, Object?>{
        'id': defId,
        'name': 'Манікюр',
        'baseDurationMinutes': 60,
        'priceType': 'FIXED',
        'priceMin': 500,
        'priceDisplay': '500 ₴',
        'isActive': true,
      },
      'isActive': true,
    };

void main() {
  late List<String> recordedUris;
  late List<Map<String, Object?>> ownRows;
  late _MockDio dio;

  setUp(() {
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    _OwnerAuth.role = UserRole.salonOwner;
    recordedUris = <String>[];
    ownRows = <Map<String, Object?>>[];
  });
  tearDown(AppStartTime.resetForTest);

  Future<GoRouter> pumpOwnerRouter(
    WidgetTester tester, {
    MySalons Function() mySalons = _SettledMySalons.new,
  }) async {
    dio = _MockDio();
    when(() => dio.get<Object?>(any())).thenAnswer((invocation) async {
      final String path = invocation.positionalArguments[0] as String;
      recordedUris.add(path);
      return Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, Object?>{
          'success': true,
          'data': List<Object?>.of(ownRows),
        },
      );
    });
    final ProviderContainer container = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        authProvider.overrideWith(_OwnerAuth.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        mySalonsProvider.overrideWith(mySalons),
        masterProfileProvider.overrideWith(_OwnerMasterProfile.new),
        dioProvider.overrideWithValue(dio),
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[],
        ),
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

  ServiceTarget? targetSeenBy(WidgetTester tester, Finder finder) =>
      ProviderScope.containerOf(
        tester.element(finder),
      ).read(serviceTargetProvider);

  testWidgets('/owner/master/services/setup resolves to ServiceSetupScreen '
      '(not ServiceEditScreen) inside the owner row scope', (tester) async {
    final GoRouter router = await pumpOwnerRouter(tester);

    router.go(RouteNames.ownerMasterServiceSetup);
    await pumpUntilFound(tester, find.byType(ServiceSetupScreen));

    expect(find.byType(ServiceSetupScreen), findsOneWidget);
    expect(find.byType(ServiceEditScreen), findsNothing);
    expect(
      tester
          .widget<ServiceSetupScreen>(find.byType(ServiceSetupScreen))
          .exitRoute,
      RouteNames.ownerMasterServices,
      reason: 'the no-stack fallback must land on the owner tab, not /services',
    );
    expect(
      targetSeenBy(tester, find.byType(ServiceSetupScreen)),
      _kOwnerTarget,
      reason:
          'the bulk-create POST must go to /salons/S/masters/M/services — the '
          'setup leaf has to sit inside the owner shell\'s ProviderScope',
    );
  });

  testWidgets('a COLD deep link to setup shows a loading state — never the '
      '«Unauthorized» error — while mySalons resolves, then the form', (
    tester,
  ) async {
    _GatedMySalons.gate = Completer<List<Salon>>();
    final GoRouter router = await pumpOwnerRouter(
      tester,
      mySalons: _GatedMySalons.new,
    );

    router.go(RouteNames.ownerMasterServiceSetup);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('salon_manage_service_setup_loading')),
    );
    expect(
      find.byKey(const Key('salon_manage_service_setup_error')),
      findsNothing,
      reason: 'an unresolved mySalons is "not known yet", not "denied"',
    );
    expect(find.byType(ServiceSetupScreen), findsNothing);

    _GatedMySalons.gate.complete(const <Salon>[
      Salon(id: _kSalonId, name: 'Test Salon', isPrimary: true),
    ]);
    await pumpUntilFound(tester, find.byType(ServiceSetupScreen));
    expect(
      find.byKey(const Key('salon_manage_service_setup_loading')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('salon_manage_service_setup_error')),
      findsNothing,
    );
  });

  testWidgets('CONTROL for the cold-link case: mySalons resolving WITHOUT this '
      'salon still renders the «Unauthorized» error, not an endless loader', (
    tester,
  ) async {
    _GatedMySalons.gate = Completer<List<Salon>>();
    final GoRouter router = await pumpOwnerRouter(
      tester,
      mySalons: _GatedMySalons.new,
    );

    router.go(RouteNames.ownerMasterServiceSetup);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('salon_manage_service_setup_loading')),
    );
    _GatedMySalons.gate.complete(const <Salon>[
      Salon(id: 'salon-someone-else', name: 'Other', isPrimary: true),
    ]);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('salon_manage_service_setup_error')),
    );
    expect(find.byType(ServiceSetupScreen), findsNothing);
  });

  testWidgets('/owner/master/services/:id/edit resolves to ServiceEditScreen '
      'with the id, writable, inside the owner row scope', (tester) async {
    final GoRouter router = await pumpOwnerRouter(tester);

    router.go(RouteNames.ownerMasterServiceEdit('svc-1'));
    await pumpUntilFound(tester, find.byType(ServiceEditScreen));

    final ServiceEditScreen screen = tester.widget<ServiceEditScreen>(
      find.byType(ServiceEditScreen),
    );
    expect(screen.id, 'svc-1');
    expect(screen.writable, isTrue);
    expect(find.byType(ServiceSetupScreen), findsNothing);
    expect(targetSeenBy(tester, find.byType(ServiceEditScreen)), _kOwnerTarget);
    for (final String uri in recordedUris) {
      expect(uri, isNot(contains('/masters/me')));
      expect(uri, isNot(contains(_kOwnerUserId)));
    }
  });

  testWidgets('pushing setup from the list stacks on the SHELL navigator: the '
      'list stays mounted underneath and pop returns to it', (tester) async {
    final GoRouter router = await pumpOwnerRouter(tester);

    router.go(RouteNames.ownerMasterServices);
    await pumpUntilFound(tester, find.byType(ServicesListScreen));
    // fixed-wait-ok: draining the entry transition before pushing.
    await tester.pump(const Duration(seconds: 1));

    // ignore: unawaited_futures — the push future completes only on pop.
    router.push<void>(RouteNames.ownerMasterServiceSetup);
    await pumpUntilFound(tester, find.byType(ServiceSetupScreen));
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);

    router.pop();
    await pumpUntilGone(tester, find.byType(ServiceSetupScreen));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, RouteNames.ownerMasterServices);
    expect(find.byType(ServicesListScreen), findsOneWidget);
  });

  testWidgets('CONTROL: an INDEPENDENT_MASTER is bounced off both drill-ins '
      '(the /owner/master/ prefix gate covers them)', (tester) async {
    _OwnerAuth.role = UserRole.independentMaster;
    final GoRouter router = await pumpOwnerRouter(tester);

    for (final String location in <String>[
      RouteNames.ownerMasterServiceSetup,
      RouteNames.ownerMasterServiceEdit('svc-1'),
    ]) {
      router.go(location);
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, isNot(startsWith('/owner/master/')));
      expect(find.byType(ServiceSetupScreen), findsNothing);
      expect(find.byType(ServiceEditScreen), findsNothing);
    }
  });

  // -------------------------------------------------------------------------
  // Phase 380 security audit — a crafted `:serviceId` and an empty one.
  // -------------------------------------------------------------------------

  /// Asserts the mock Dio carried NO write of any verb: the generated client
  /// goes through `request`, the raw unassign path through `delete`.
  void expectNoWrites() {
    verifyNever(
      () => dio.delete<Object?>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    );
    verifyNever(
      () => dio.patch<Object?>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onSendProgress: any(named: 'onSendProgress'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      ),
    );
    verifyNever(
      () => dio.request<Object?>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
        onSendProgress: any(named: 'onSendProgress'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      ),
    );
  }

  testWidgets('SECURITY: a crafted serviceId NOT in the owner\'s own-row '
      'catalogue renders the NotFound error state — no form, no delete, ZERO '
      'PATCH/DELETE calls', (tester) async {
    ownRows = <Map<String, Object?>>[_ownRow('svc-own', 'def-own')];
    final GoRouter router = await pumpOwnerRouter(tester);

    router.go(RouteNames.ownerMasterServiceEdit('svc-foreign-salon-row'));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service_edit_error_state')),
    );

    final ErrorState error = tester.widget<ErrorState>(
      find.byKey(const Key('service_edit_error_state')),
    );
    expect(error.failure, isA<NotFoundFailure>());
    expect(find.byKey(const Key('btn-delete-service')), findsNothing);
    expect(
      find.byKey(const Key('service-edit-form-svc-foreign-salon-row')),
      findsNothing,
    );
    expect(
      recordedUris,
      contains(
        '/api/v1/salons/$_kSalonId/masters/$_kOwnerMasterRowId/services',
      ),
      reason: 'the lookup must read the OWN-row catalogue, nothing wider',
    );
    expectNoWrites();
  });

  testWidgets('CONTROL for the crafted-id case: an id that IS in the own-row '
      'catalogue mounts the writable form with delete', (tester) async {
    ownRows = <Map<String, Object?>>[_ownRow('svc-own', 'def-own')];
    final GoRouter router = await pumpOwnerRouter(tester);

    router.go(RouteNames.ownerMasterServiceEdit('svc-own'));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-svc-own')),
    );

    expect(find.byKey(const Key('service_edit_error_state')), findsNothing);
    expect(find.byKey(const Key('btn-delete-service')), findsOneWidget);
    expectNoWrites();
  });

  // go_router compiles `:serviceId` to `[^/]+`, so `//edit` never matches
  // the edit route (the former empty-id `redirect` there was dead and is
  // gone): it is a router-level no-match, which `appRouter`'s `onException`
  // sends to the owner's role home. Pinned here together with the safety
  // property: no ServiceEditScreen, no own-row read, no write.
  testWidgets('an EMPTY serviceId (`/owner/master/services//edit`) lands on '
      'the owner\'s role home — no edit screen, no read or write', (
    tester,
  ) async {
    final GoRouter router = await pumpOwnerRouter(tester);
    recordedUris.clear();

    router.go(RouteNames.ownerMasterServiceEdit(''));
    await pumpUntil(
      tester,
      () =>
          // router-location-ok: waiting on the post-onException landing.
          router.routerDelegate.currentConfiguration.uri.path ==
          roleHomePath(UserRole.salonOwner),
    );

    final Uri landed =
        // router-location-ok: asserting the post-onException landing.
        router.routerDelegate.currentConfiguration.uri;
    expect(landed.path, roleHomePath(UserRole.salonOwner));
    expect(router.routerDelegate.currentConfiguration.error, isNull);
    expect(find.text('Page Not Found'), findsNothing);
    expect(find.byType(ServiceEditScreen), findsNothing);
    expect(find.byType(ServiceSetupScreen), findsNothing);
    expect(recordedUris, isEmpty);
    expectNoWrites();
  });
}
