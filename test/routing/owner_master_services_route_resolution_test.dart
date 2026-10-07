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
// Phase 381 (24.1d) — the «Графік» tab (`/owner/master/schedule`) shares
// this harness: it pins the mounted [MasterScheduleScreen]'s scope (the
// owner's OWN row in the primary salon — never the empty
// `ownScheduleScopeProvider` id an owner would get), the canonical tile-2
// bar, the «‹ Салон» back, and that every schedule read is keyed on the own
// master row, never `/masters/me`.
//
// Phase 383 (24.1f) — the «Записи» tab (`/owner/master/bookings`) and its
// «Архів» share it too: the mounted [MasterBookingsScreen] /
// [MasterArchiveScreen] are the owner-row scope (`asOwnerMaster: true`), the
// tile-1 bar routes all four tiles to `/owner/master/*`, detail/review reuse
// `/salon/bookings/*`, and every `GET /bookings/me` carries `asMaster: true`.
// Plus two 381 perf carry-overs: the «Графік» capability skeleton has its own
// key, and leaving master mode releases the shell's roster keep-alive.
//
// Layer: Widget (real appRouterProvider + authRedirect, faked providers).

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
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
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
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

/// Phase 381 — the owner's primary-salon roster WITH their own auto-enrolled
/// master row, which `scheduleEditable`'s owner arm requires.
class _RosterWithOwnRow extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async => (
    const Salon(id: _kSalonId, name: 'Test Salon', isPrimary: true),
    const <SalonStaffMember>[
      SalonStaffMember(
        userId: _kOwnerUserId,
        masterId: _kOwnerMasterRowId,
        role: SalonStaffRole.master,
        firstName: 'Олена',
        lastName: 'Ковальчук',
      ),
    ],
  );
}

/// Phase 381 QA — [_RosterWithOwnRow] that counts its builds. The FIRST
/// build answers at once; every REFETCH is held on [refetchGate] — a real
/// `GET /salons/{id}` takes network time, which an instantly-resolving fake
/// would hide (the read-only window would be zero frames long).
class _CountingRoster extends _RosterWithOwnRow {
  static int builds = 0;
  static Completer<void> refetchGate = Completer<void>();

  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    builds++;
    if (builds > 1) await refetchGate.future;
    return super.build(salonId);
  }
}

/// Phase 381 QA — the ACCOUNT-SWITCH case: an owner session whose user can be
/// replaced in place ([signInAs]), as a logout of owner A followed by a login
/// of owner B does to `authProvider`.
class _SwitchableOwnerAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: _ownerUser(_kOwnerUserId),
    accessToken: 'token-a',
  );

  void signInAs(String userId) => state = AsyncData<AuthSession>(
    AuthSession.authenticated(user: _ownerUser(userId), accessToken: 'token-b'),
  );
}

User _ownerUser(String id) => User(
  id: id,
  email: '$id@beautica.test',
  role: UserRole.salonOwner,
  hasMasterProfile: true,
);

const String _kOwnerBUserId = 'user-owner-B';
const String _kOwnerBMasterRowId = 'master-row-owner-B';
const String _kSalonBId = 'salon-owner-B';

/// Phase 381 QA — `masterProfileProvider` keyed on the session's user id the
/// way production's is (`master_profile_notifier.dart:111`): owner A resolves
/// at once; owner B's `GET /masters/me` is held on [ownerBGate], so the test
/// can observe every frame of the reload that carries A's retained value.
class _PerUserMasterProfile extends MasterProfile {
  static Completer<Master> ownerBGate = Completer<Master>();

  @override
  Future<Master> build() async {
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    if (userId == _kOwnerBUserId) return ownerBGate.future;
    return const Master(
      id: _kOwnerMasterRowId,
      firstName: 'Олена',
      lastName: 'Ковальчук',
      reviewCount: 0,
      type: MasterType.salonOwner,
      salonId: _kSalonId,
    );
  }
}

class _MockDio extends Mock implements Dio {}

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

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
    SalonManagementProfile Function() roster = _RosterWithOwnRow.new,
    MasterProfile Function() masterProfile = _OwnerMasterProfile.new,
    AuthNotifier Function() auth = _OwnerAuth.new,
    List<Object> extraOverrides = const <Object>[],
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
        authProvider.overrideWith(auth),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        mySalonsProvider.overrideWith(mySalons),
        masterProfileProvider.overrideWith(masterProfile),
        dioProvider.overrideWithValue(dio),
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[],
        ),
        salonManagementProfileProvider.overrideWith(roster),
        ...extraOverrides,
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
  // -------------------------------------------------------------------------
  // Phase 381 (24.1d) — «Графік».
  // -------------------------------------------------------------------------

  /// Answers every generated-client `request` (the schedule reads) with an
  /// empty list, recording the path.
  void stubScheduleReads() {
    when(
      () => dio.request<Object>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
        onSendProgress: any(named: 'onSendProgress'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      ),
    ).thenAnswer((invocation) async {
      final String path = invocation.positionalArguments[0] as String;
      recordedUris.add(path);
      return Response<Object>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, Object?>{'success': true, 'data': <Object?>[]},
      );
    });
  }

  /// The schedule providers pin themselves for a 5-minute TTL
  /// (`EffectiveScheduleNotifier._pinForTtl`, `OverridesNotifier`); fire
  /// those fake timers before the test ends.
  Future<void> drainScheduleTtl(WidgetTester tester) =>
      // fixed-wait-ok: TTL crossing — must exceed the 5-minute keepAlive pin.
      tester.pump(const Duration(minutes: 6));

  testWidgets('/owner/master/schedule mounts MasterScheduleScreen on the '
      'owner\'s OWN row (primary salon), tile-2 owner bar, «‹ Салон» back, '
      'editable; every schedule read is keyed on the own master row', (
    tester,
  ) async {
    final GoRouter router = await pumpOwnerRouter(tester);
    stubScheduleReads();
    recordedUris.clear();

    router.go(RouteNames.ownerMasterSchedule);
    await pumpUntilFound(tester, find.byType(MasterScheduleScreen));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('no-schedule-add-hours')),
    );

    expect(router.state.matchedLocation, RouteNames.ownerMasterSchedule);
    final MasterScheduleScreen screen = tester.widget<MasterScheduleScreen>(
      find.byType(MasterScheduleScreen),
    );
    expect(
      screen.scope,
      const ScheduleScope.salonMaster(
        salonId: _kSalonId,
        masterId: _kOwnerMasterRowId,
      ),
      reason:
          'a null scope resolves through ownScheduleScopeProvider, which is '
          'EMPTY for SALON_OWNER — the owner tab must pass its own row',
    );
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(MasterScheduleScreen)),
    );
    expect(screen.backLabel, l10n.ownerMasterModeBack);
    expect(screen.backSemanticLabel, l10n.ownerMasterModeBackSemantics);
    expect(screen.onBack, isNotNull);

    final VelvetBottomNavBar bar = tester.widget<VelvetBottomNavBar>(
      find.byType(VelvetBottomNavBar),
    );
    expect(bar.activeIndex, 2);
    expect(bar.servicesRoute, RouteNames.ownerMasterServices);
    expect(bar.scheduleRoute, RouteNames.ownerMasterSchedule);
    expect(bar.profileRoute, RouteNames.ownerMasterProfile);

    // The CTA only renders for an EDITABLE viewer (scheduleEditable's owner
    // arm: managed salon + own row on its roster).
    expect(find.byKey(const Key('no-schedule-add-hours')), findsOneWidget);

    expect(
      recordedUris,
      contains('/api/v1/masters/$_kOwnerMasterRowId/weekly-schedules'),
    );
    for (final String uri in recordedUris) {
      expect(uri, isNot(contains('/masters/me')));
      expect(uri, isNot(contains(_kOwnerUserId)));
    }
    await drainScheduleTtl(tester);
  });

  testWidgets('«‹ Салон» on the schedule tab goes to the salon resolver', (
    tester,
  ) async {
    final GoRouter router = await pumpOwnerRouter(tester);
    stubScheduleReads();

    router.go(RouteNames.ownerMasterSchedule);
    await pumpUntilFound(tester, find.byType(MasterScheduleScreen));
    final MasterScheduleScreen screen = tester.widget<MasterScheduleScreen>(
      find.byType(MasterScheduleScreen),
    );
    screen.onBack?.call();
    await pumpUntil(
      tester,
      () => router.state.matchedLocation != RouteNames.ownerMasterSchedule,
    );
    await pumpUntilGone(tester, find.byType(MasterScheduleScreen));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, isNot(startsWith('/owner/master/')));
    // Phase 381 QA — pin the DESTINATION, not just "left master mode": the
    // salon resolver lands on the owner's primary salon shell.
    expect(router.state.matchedLocation, RouteNames.salonShell(_kSalonId));
    await drainScheduleTtl(tester);
  });

  testWidgets('CONTROL: an INDEPENDENT_MASTER is bounced off '
      '/owner/master/schedule (the prefix gate covers it)', (tester) async {
    _OwnerAuth.role = UserRole.independentMaster;
    final GoRouter router = await pumpOwnerRouter(tester);
    stubScheduleReads();

    router.go(RouteNames.ownerMasterSchedule);
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, isNot(startsWith('/owner/master/')));
  });

  // -------------------------------------------------------------------------
  // Phase 381 QA — the owner nav table and the two audit findings.
  // -------------------------------------------------------------------------

  testWidgets('every reachable owner tab\'s bar routes tile 2 to '
      '/owner/master/schedule (the one `_kOwnerMasterNavBars` table), and '
      'tapping it from «Послуги» lands on «Графік»', (tester) async {
    final GoRouter router = await pumpOwnerRouter(tester);
    stubScheduleReads();

    for (final String tab in <String>[
      RouteNames.ownerMasterServices,
      RouteNames.ownerMasterProfile,
    ]) {
      router.go(tab);
      await pumpUntil(tester, () => router.state.matchedLocation == tab);
      await pumpUntilFound(tester, find.byType(VelvetBottomNavBar));
      expect(
        tester
            .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
            .scheduleRoute,
        RouteNames.ownerMasterSchedule,
        reason: '$tab bar must route «Графік» to the owner tab, not /schedule',
      );
    }

    router.go(RouteNames.ownerMasterServices);
    await pumpUntilFound(tester, find.byType(ServicesListScreen));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('master-nav-tile-2')));
    await pumpUntilFound(tester, find.byType(MasterScheduleScreen));
    expect(router.state.matchedLocation, RouteNames.ownerMasterSchedule);
    await drainScheduleTtl(tester);
  });

  // SPEC — audit MEDIUM (perf): `salonManagementProfileProvider` is
  // autoDispose, so leaving «Графік» drops the roster and every re-entry
  // refetches it while the (TTL-cached) schedule is already resolved —
  // `scheduleEditable` is false for that window, so the read-only banner
  // (no «Додати години» CTA) flashes before the editable one. Planned fix:
  // the owner shell keeps the roster alive while in master mode + a loading
  // skeleton while the capability is pending. FIXED (phase 381 audit).
  testWidgets(
    'SPEC (perf MEDIUM): re-entering «Графік» never shows a read-only frame '
    'before the editable one, and the roster is fetched once per visit',
    (tester) async {
      _CountingRoster.builds = 0;
      _CountingRoster.refetchGate = Completer<void>();
      final GoRouter router = await pumpOwnerRouter(
        tester,
        roster: _CountingRoster.new,
      );
      stubScheduleReads();
      final Finder addHours = find.byKey(const Key('no-schedule-add-hours'));
      final Finder banner = find.byType(NoScheduleBanner);

      router.go(RouteNames.ownerMasterSchedule);
      await pumpUntilFound(tester, addHours);

      // Away to another master-mode tab and back (the schedule itself stays
      // TTL-cached, so only the roster can make the second entry read-only).
      for (final String away in <String>[
        RouteNames.ownerMasterServices,
        RouteNames.ownerMasterProfile,
      ]) {
        router.go(away);
        await pumpUntil(tester, () => router.state.matchedLocation == away);
        // Wait for the schedule page to UNMOUNT (end of the tab transition):
        // only then does the autoDispose roster lose its last listener.
        await pumpUntilGone(
          tester,
          find.byType(MasterScheduleScreen, skipOffstage: false),
        );
        await tester.pump();
      }

      router.go(RouteNames.ownerMasterSchedule);
      // 40 × one 60 Hz frame (640 ms) — spans the tab transition, so every
      // frame the user would SEE is inspected.
      for (int frame = 0; frame < 40; frame++) {
        // fixed-wait-ok: frame-stepping (one vsync), not a wait for a result.
        await tester.pump(const Duration(milliseconds: 16));
        if (banner.evaluate().isNotEmpty) {
          expect(
            addHours,
            findsWidgets,
            reason:
                'frame $frame: the schedule rendered READ-ONLY (banner without '
                'the CTA) while the roster was refetched',
          );
        }
      }
      expect(addHours, findsOneWidget);
      if (!_CountingRoster.refetchGate.isCompleted) {
        _CountingRoster.refetchGate.complete();
      }
      expect(
        _CountingRoster.builds,
        1,
        reason: 'the roster must survive a tab switch inside master mode',
      );
      await drainScheduleTtl(tester);
    },
  );

  // SPEC — audit LOW (security): `_selectOwnMasterIds`
  // (`app_router.dart` `_selectOwnMasterIds`) reads the lenient `.value`, so
  // while `masterProfileProvider` RELOADS for a new session it still carries
  // the previous owner's (salonId, masterId) and `_OwnMasterRowGate` builds
  // the previous owner's schedule scope. Planned fix: null the ids when
  // `async.isReloading`. FIXED (phase 381 audit).
  testWidgets(
    'SPEC (security LOW): owner A → owner B, while B\'s profile loads the gate '
    'shows the loading skeleton — never a schedule scoped on A\'s row',
    (tester) async {
      _PerUserMasterProfile.ownerBGate = Completer<Master>();
      final GoRouter router = await pumpOwnerRouter(
        tester,
        masterProfile: _PerUserMasterProfile.new,
        auth: _SwitchableOwnerAuth.new,
      );
      stubScheduleReads();
      router.go(RouteNames.ownerMasterSchedule);
      await pumpUntilFound(tester, find.byType(MasterScheduleScreen));

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MasterScheduleScreen)),
      );
      (container.read(authProvider.notifier) as _SwitchableOwnerAuth).signInAs(
        _kOwnerBUserId,
      );

      for (int frame = 0; frame < 10; frame++) {
        await tester.pump();
        for (final MasterScheduleScreen s
            in tester.widgetList<MasterScheduleScreen>(
              find.byType(MasterScheduleScreen),
            )) {
          expect(
            s.scope?.masterId,
            isNot(_kOwnerMasterRowId),
            reason: 'frame $frame: owner B saw owner A\'s schedule scope',
          );
        }
      }
      expect(
        find.byKey(const Key('salon_master_own_services_loading')),
        findsOneWidget,
      );

      _PerUserMasterProfile.ownerBGate.complete(
        const Master(
          id: _kOwnerBMasterRowId,
          firstName: 'Ірина',
          lastName: 'Бондар',
          reviewCount: 0,
          type: MasterType.salonOwner,
          salonId: _kSalonBId,
        ),
      );
      await pumpUntilFound(tester, find.byType(MasterScheduleScreen));
      expect(
        tester
            .widget<MasterScheduleScreen>(find.byType(MasterScheduleScreen))
            .scope,
        const ScheduleScope.salonMaster(
          salonId: _kSalonBId,
          masterId: _kOwnerBMasterRowId,
        ),
      );
      await drainScheduleTtl(tester);
    },
  );

  // -------------------------------------------------------------------------
  // Phase 381 perf INFO carry-overs (landed in 383).
  // -------------------------------------------------------------------------

  testWidgets('the «Графік» capability skeleton (mySalons pending) carries '
      'its OWN key — never the services gate\'s', (tester) async {
    _GatedMySalons.gate = Completer<List<Salon>>();
    final GoRouter router = await pumpOwnerRouter(
      tester,
      mySalons: _GatedMySalons.new,
    );
    stubScheduleReads();

    router.go(RouteNames.ownerMasterSchedule);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('owner_master_schedule_loading')),
    );
    expect(
      find.byKey(const Key('salon_master_own_services_loading')),
      findsNothing,
    );
    expect(find.byType(MasterScheduleScreen), findsNothing);

    _GatedMySalons.gate.complete(const <Salon>[
      Salon(id: _kSalonId, name: 'Test Salon', isPrimary: true),
    ]);
    await pumpUntilFound(tester, find.byType(MasterScheduleScreen));
    expect(
      find.byKey(const Key('owner_master_schedule_loading')),
      findsNothing,
    );
    await drainScheduleTtl(tester);
  });

  /// The salon shell runs a perpetual loading animation in this harness, so
  /// `pumpAndSettle` never returns there — step a bounded number of frames
  /// (spans the page transition) instead.
  Future<void> settleFrames(WidgetTester tester) async {
    for (int frame = 0; frame < 60; frame++) {
      // fixed-wait-ok: frame-stepping (one vsync), not a wait for a result.
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // MUTATION: replaced the shell's `ref.listen(...)` with a container-level
  // `ProviderScope.containerOf(context).listen(...)` that is never closed (the
  // leak class this pins) → `exists` stayed true on the roster-free page,
  // this test failed. Restored.
  testWidgets('leaving master mode via «‹ Салон» RELEASES the owner shell\'s '
      'roster keep-alive: the shell unmounts, and once the salon side is left '
      'too the roster is disposed', (tester) async {
    final GoRouter router = await pumpOwnerRouter(tester);
    stubScheduleReads();
    final Finder masterShell = find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == '_SalonMasterTabsShell',
      skipOffstage: false,
    );
    ProviderContainer containerNow() =>
        ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

    // Master mode on «Профіль» — a tab whose screen never reads the roster,
    // so the shell's keep-alive listen is what holds it.
    router.go(RouteNames.ownerMasterProfile);
    await pumpUntil(
      tester,
      () => router.state.matchedLocation == RouteNames.ownerMasterProfile,
    );
    await settleFrames(tester);
    expect(masterShell, findsOneWidget, reason: 'fixture guard');
    expect(
      containerNow().exists(salonManagementProfileProvider(_kSalonId)),
      isTrue,
      reason: 'fixture guard: the owner shell keeps the roster alive',
    );

    // «‹ Салон» — the SAME `go(salonHome)` every owner tab's back runs.
    router.go(RouteNames.salonHome);
    await pumpUntilFound(tester, find.byType(SalonManagementProfileScreen));
    await settleFrames(tester);
    expect(
      masterShell,
      findsNothing,
      reason: 'the master-mode shell (and its listen) must be gone',
    );

    // The salon profile tab legitimately watches the roster; leave it for a
    // roster-free owner page. With no leaked holder the autoDispose roster
    // must now be disposed.
    router.go(RouteNames.ownerEditPersonal);
    await pumpUntil(
      tester,
      () => router.state.matchedLocation == RouteNames.ownerEditPersonal,
    );
    await pumpUntilGone(
      tester,
      find.byType(SalonManagementProfileScreen, skipOffstage: false),
    );
    await settleFrames(tester);
    expect(
      containerNow().exists(salonManagementProfileProvider(_kSalonId)),
      isFalse,
      reason: 'nothing may keep the roster alive after master mode is left',
    );
    await drainScheduleTtl(tester);
  });

  // -------------------------------------------------------------------------
  // Phase 383 (24.1f) — «Записи» + «Архів».
  // -------------------------------------------------------------------------

  group('«Записи» (/owner/master/bookings)', () {
    late _MockBookingRepository bookingRepo;
    late List<bool> asMasterSeen;

    setUpAll(() {
      registerFallbackValue(BookingStatus.confirmed);
      registerFallbackValue(BookingSort.oldest);
      registerFallbackValue(<BookingStatus>[]);
      registerFallbackValue(DateTime(2026));
    });

    setUp(() {
      bookingRepo = _MockBookingRepository();
      asMasterSeen = <bool>[];
      when(
        () => bookingRepo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          partition: any(named: 'partition'),
          asMaster: any(named: 'asMaster'),
        ),
      ).thenAnswer((Invocation i) async {
        asMasterSeen.add(i.namedArguments[#asMaster] as bool? ?? false);
        return const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        );
      });
      when(
        () => bookingRepo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
          asMaster: any(named: 'asMaster'),
        ),
      ).thenAnswer((Invocation i) async {
        asMasterSeen.add(i.namedArguments[#asMaster] as bool? ?? false);
        return <DateTime>[];
      });
    });

    /// The booked-days dots pin themselves for 30 minutes
    /// (`_bookedDaysWindow`'s keepAlive timer) — longer than the schedule's
    /// 5-minute TTL, so this drain covers both.
    Future<void> drainBookingsTtl(WidgetTester tester) =>
        // fixed-wait-ok: TTL crossing — must exceed the 30-minute keepAlive.
        tester.pump(const Duration(minutes: 31));

    List<Object> bookingOverrides() => <Object>[
      bookingRepositoryProvider.overrideWithValue(bookingRepo),
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    ];

    testWidgets('mounts MasterBookingsScreen on the owner-row scope: '
        'asOwnerMaster, /salon/* detail, owner archive, tile-1 bar with all '
        'four owner routes, «‹ Салон»; every /bookings/me read is asMaster', (
      tester,
    ) async {
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      stubScheduleReads();

      router.go(RouteNames.ownerMasterBookings);
      await pumpUntilFound(tester, find.byType(MasterBookingsScreen));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.ownerMasterBookings);
      final MasterBookingsScreen screen = tester.widget<MasterBookingsScreen>(
        find.byType(MasterBookingsScreen),
      );
      expect(screen.asOwnerMaster, isTrue);
      expect(screen.detailRouteBuilder?.call('b1'), '/salon/bookings/b1');
      expect(screen.archiveRoute, RouteNames.ownerMasterBookingsArchive);
      expect(screen.navScheduleRoute, RouteNames.ownerMasterSchedule);
      expect(screen.canAddWorkingHours, isTrue);
      expect(
        screen.scheduleScope,
        const ScheduleScope.salonMaster(
          salonId: _kSalonId,
          masterId: _kOwnerMasterRowId,
        ),
        reason:
            'the working-hours window must read the owner\'s OWN row, not '
            'the empty own scope ownScheduleScopeProvider gives an owner',
      );
      expect(screen.detailExtra, _kSalonId);
      expect(
        recordedUris,
        contains('/api/v1/masters/$_kOwnerMasterRowId/effective-schedule'),
      );
      // The filter sheet's «Послуга» options: the owner-row catalogue via the
      // shell's scope — never `/independent-masters/me/services`.
      expect(
        recordedUris,
        contains(
          '/api/v1/salons/$_kSalonId/masters/$_kOwnerMasterRowId/services',
        ),
      );
      for (final String uri in recordedUris) {
        expect(uri, isNot(contains('/masters/me')));
      }
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MasterBookingsScreen)),
      );
      expect(screen.backLabel, l10n.ownerMasterModeBack);
      expect(screen.backSemanticLabel, l10n.ownerMasterModeBackSemantics);
      expect(find.byKey(const Key('bookings-discovery-back')), findsOneWidget);

      final VelvetBottomNavBar bar = tester.widget<VelvetBottomNavBar>(
        find.byType(VelvetBottomNavBar),
      );
      expect(bar.activeIndex, 1);
      expect(bar.servicesRoute, RouteNames.ownerMasterServices);
      expect(bar.bookingsRoute, RouteNames.ownerMasterBookings);
      expect(bar.scheduleRoute, RouteNames.ownerMasterSchedule);
      expect(bar.profileRoute, RouteNames.ownerMasterProfile);

      expect(asMasterSeen, isNotEmpty);
      expect(
        asMasterSeen,
        everyElement(isTrue),
        reason: 'owner master mode must never read the salon-wide list/dots',
      );
      await drainBookingsTtl(tester);
    });

    // Phase 383 — decision 2026-10-07: (+) books the owner's OWN row via the
    // independent master's walk-in chain, mounted inside the owner shell.
    testWidgets('(+) opens the owner walk-in chain (/owner/master/bookings/'
        'new) — never the salon wizard (master-pick step) nor /master/*', (
      tester,
    ) async {
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      stubScheduleReads();

      router.go(RouteNames.ownerMasterBookings);
      await pumpUntilFound(tester, find.byType(MasterBookingsScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('master-bookings-add')));
      await pumpUntilFound(tester, find.byType(WalkInGuestStepScreen));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        RouteNames.ownerMasterBookingNew,
      );
      expect(find.byType(SalonCreateBookingScreen), findsNothing);
      expect(
        tester
            .widget<WalkInGuestStepScreen>(find.byType(WalkInGuestStepScreen))
            .servicesRoute,
        RouteNames.ownerMasterBookingNewServices,
      );
      await drainBookingsTtl(tester);
    });

    testWidgets('the owner walk-in service step resolves INSIDE the owner '
        'row scope: lists /salons/S/masters/M/services (never '
        '/independent-masters/me/services) and returns to the owner «Записи»', (
      tester,
    ) async {
      ownRows.add(_ownRow('own-svc-1', 'def-1'));
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      stubScheduleReads();

      router.go(RouteNames.ownerMasterBookings);
      await pumpUntilFound(tester, find.byType(MasterBookingsScreen));
      await tester.pumpAndSettle();
      unawaited(router.push(RouteNames.ownerMasterBookingNew));
      await pumpUntilFound(tester, find.byType(WalkInGuestStepScreen));
      unawaited(
        router.push(
          RouteNames.ownerMasterBookingNewServices,
          extra: const WalkInGuest(
            name: 'Анна',
            surname: 'Гість',
            phone: '+380501234567',
          ),
        ),
      );
      await pumpUntilFound(tester, find.byType(WalkInServiceStepScreen));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        RouteNames.ownerMasterBookingNewServices,
      );
      final Finder step = find.byType(WalkInServiceStepScreen);
      expect(targetSeenBy(tester, step), _kOwnerTarget);
      expect(
        tester.widget<WalkInServiceStepScreen>(step).returnRoute,
        RouteNames.ownerMasterBookings,
      );
      expect(
        recordedUris,
        contains(
          '/api/v1/salons/$_kSalonId/masters/$_kOwnerMasterRowId/services',
        ),
      );
      for (final String uri in recordedUris) {
        expect(uri, isNot(contains('/independent-masters/me/services')));
      }
      // The owner-row catalogue row renders in the step's list.
      expect(
        // i18n-finder-ok: server fixture service name (`_ownRow`), not UI copy
        find.descendant(of: step, matching: find.text('Манікюр')),
        findsWidgets,
      );
      await drainBookingsTtl(tester);
    });

    testWidgets('a COLD deep link to the owner services step with no guest '
        'extra bounces to the owner guest step', (tester) async {
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      router.go(RouteNames.ownerMasterBookingNewServices);
      await pumpUntilFound(tester, find.byType(WalkInGuestStepScreen));
      expect(router.state.matchedLocation, RouteNames.ownerMasterBookingNew);
      expect(find.byType(WalkInServiceStepScreen), findsNothing);
      await drainBookingsTtl(tester);
    });

    testWidgets('the «Мої записи» tile on every other owner tab lands on '
        '/owner/master/bookings (never the INDEPENDENT_MASTER /master/*)', (
      tester,
    ) async {
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      stubScheduleReads();

      for (final String tab in <String>[
        RouteNames.ownerMasterServices,
        RouteNames.ownerMasterSchedule,
        RouteNames.ownerMasterProfile,
      ]) {
        router.go(tab);
        await pumpUntil(tester, () => router.state.matchedLocation == tab);
        await pumpUntilFound(tester, find.byType(VelvetBottomNavBar));
        expect(
          tester
              .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
              .bookingsRoute,
          RouteNames.ownerMasterBookings,
          reason: '$tab bar must route «Мої записи» to the owner tab',
        );
      }

      router.go(RouteNames.ownerMasterProfile);
      await pumpUntil(
        tester,
        () => router.state.matchedLocation == RouteNames.ownerMasterProfile,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await pumpUntilFound(tester, find.byType(MasterBookingsScreen));
      expect(router.state.matchedLocation, RouteNames.ownerMasterBookings);
      await drainBookingsTtl(tester);
    });

    testWidgets('«Архів» resolves to MasterArchiveScreen on the owner-row '
        'scope with /salon/* detail + review, and reads asMaster', (
      tester,
    ) async {
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      stubScheduleReads();

      router.go(RouteNames.ownerMasterBookingsArchive);
      await pumpUntilFound(tester, find.byType(MasterArchiveScreen));
      await tester.pumpAndSettle();

      expect(
        router.state.matchedLocation,
        RouteNames.ownerMasterBookingsArchive,
      );
      expect(find.byType(MasterBookingsScreen), findsNothing);
      final MasterArchiveScreen archive = tester.widget<MasterArchiveScreen>(
        find.byType(MasterArchiveScreen),
      );
      expect(archive.asOwnerMaster, isTrue);
      expect(archive.salonId, isNull);
      expect(archive.detailRouteBuilder?.call('b1'), '/salon/bookings/b1');
      expect(
        archive.reviewRouteBuilder?.call('b1'),
        '/salon/bookings/b1/review',
      );
      expect(asMasterSeen, isNotEmpty);
      expect(asMasterSeen, everyElement(isTrue));
      await drainBookingsTtl(tester);
    });

    testWidgets('«‹ Салон» on «Записи» goes to the salon resolver', (
      tester,
    ) async {
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      stubScheduleReads();

      router.go(RouteNames.ownerMasterBookings);
      await pumpUntilFound(tester, find.byType(MasterBookingsScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bookings-discovery-back')));
      await pumpUntil(
        tester,
        () => router.state.matchedLocation == RouteNames.salonShell(_kSalonId),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MasterBookingsScreen), findsNothing);
      await drainBookingsTtl(tester);
    });

    testWidgets('CONTROL: an INDEPENDENT_MASTER is bounced off '
        '/owner/master/bookings, its archive and the owner walk-in chain', (
      tester,
    ) async {
      _OwnerAuth.role = UserRole.independentMaster;
      final GoRouter router = await pumpOwnerRouter(
        tester,
        extraOverrides: bookingOverrides(),
      );
      for (final String loc in <String>[
        RouteNames.ownerMasterBookings,
        RouteNames.ownerMasterBookingsArchive,
        RouteNames.ownerMasterBookingNew,
        RouteNames.ownerMasterBookingNewServices,
      ]) {
        router.go(loc);
        await tester.pumpAndSettle();
        expect(
          router.state.matchedLocation,
          isNot(startsWith('/owner/master/')),
        );
      }
      await drainBookingsTtl(tester);
    });
  });
}
