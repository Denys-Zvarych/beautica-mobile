// Phase 322 (mobile-qa LOW follow-up) — route-level propagation test for
// `_SalonManageServicesListRoute` and `_SalonManageServiceEditRoute`
// (`app_router.dart:2296-2350`).
//
// WHAT THIS FILE PINS, and why it cannot pass vacuously
// -------------------------------------------------------------------------
// Both wrappers watch `canManageSalonProvider(salonId)` and feed the result
// into `ServicesListScreen`/`ServiceEditScreen` as `writable:`. Before this
// file, that wiring was exercised only by the two salon-staff integration
// flows — nothing drove the REAL router through both a true AND a false
// outcome and asserted the propagated affordance directly (mobile-qa: "the
// thinnest point in the coverage").
//
//   1. TRUE  — a SALON_ADMIN of THIS salon (admitted synchronously by
//      `salonManageGuard`'s admin arm, which reads `User.salonId` off the
//      already-settled session) sees the FAB / delete affordance AND the
//      underlying content renders — a positive assertion pairs every
//      absence assertion in the FALSE case below.
//   2. FALSE — a SALON_OWNER admitted through `salonManageGuard`'s
//      documented "`mySalonsProvider` not resolved yet -> ADMIT" cold-deep-
//      link fallback (`app_router.dart` salonManageGuard, owner arm's own
//      comment) — reproduced here with `mySalonsProvider` held on a
//      never-completing `Completer` (`_UnresolvedMySalons`, see its own doc
//      for why an eagerly-settling stub does NOT reproduce this case).
//      `canManageSalonProvider`'s owner arm requires a genuinely SETTLED
//      `AsyncData` before it will say yes (`mySalons is! AsyncData ->
//      false`), so it independently refuses to treat "still unresolved" as
//      "safe to write" — the defense-in-depth Phase 322 (D1) exists for.
//      FAB absent, but the underlying content still renders (paired
//      positive) because the roster/list fetch has nothing to do with
//      `mySalonsProvider` at all.
//
// Both outcomes are asserted twice: once via the rendered AFFORDANCE key
// (`btn-create-service` / `btn-delete-service`), and once via the widget's
// own `writable` field — the field read alone would be vacuous
// (`project_widget_field_assertion_is_vacuous`), so it is never the only
// assertion in a case.
//
// MECHANISM (REUSE-FIRST, not invented): reuses
// `salon_manage_staff_services_route_test.dart`'s exact fixture shape (same
// Dio-level stub returning `salonRows` for every GET, same roster shape)
// since this file targets the SAME `/salons/:salonId/manage/staff/:memberId
// /services(...)` subtree — plus `salon_manage_capability_test.dart`'s and
// `salon_manage_route_guard_test.dart`'s shared "leave `mySalonsProvider`
// UNRESOLVED" idea for the FALSE case. Neither sibling file's private
// classes are imported (test files do not export across files in this
// repo's convention, per that file's own note); this file keeps its own
// minimal local copies of the same shapes.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/route_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-S';
const String _kMemberUserId = 'user-U';
const String _kMasterRowId = 'master-M';

const User _kAdminSameSalon = User(
  id: 'admin-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Тест',
  lastName: 'Адмін',
  salonId: _kSalonId,
);

const User _kOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Тест',
  lastName: 'Власник',
);

const SalonStaffMember _kMasterEntry = SalonStaffMember(
  userId: _kMemberUserId,
  masterId: _kMasterRowId,
  role: SalonStaffRole.master,
  firstName: 'Майстер',
  lastName: 'Один',
);

Map<String, Object?> _serviceRow({
  required String assignmentId,
  required String defId,
  required String name,
}) => <String, Object?>{
  'id': assignmentId,
  'masterId': _kMasterRowId,
  'serviceDefinition': <String, Object?>{
    'id': defId,
    'name': name,
    'baseDurationMinutes': 60,
    'priceType': 'FIXED',
    'priceMin': 500,
    'priceDisplay': '500 ₴',
    'isActive': true,
  },
  'isActive': true,
};

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _MutableAuthNotifier extends AuthNotifier {
  static User seed = _kAdminSameSalon;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: seed, accessToken: 'tok');
}

/// Role-agnostic roster stub, mirroring
/// `salon_manage_staff_services_route_test.dart`'s `_ControlledRoster` minus
/// its loading/failure gates — this file needs only the settled case.
class _StubRoster extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async => (
    const Salon(id: _kSalonId, name: 'Салон'),
    const <SalonStaffMember>[_kMasterEntry],
  );
}

/// Mirrors `salon_manage_capability_test.dart`'s `_UnresolvedMySalons` and
/// `salon_manage_route_guard_test.dart`'s own "leave `mySalonsProvider`
/// UNRESOLVED" precedent for exercising `salonManageGuard`'s owner arm
/// "not resolved yet -> ADMIT" branch — this is the FALSE case's driver.
///
/// MEASURED, not assumed: an eagerly-`async`-resolving stub does NOT work
/// here. Mounting the app for an authenticated SALON_OWNER always lands on
/// the role-home resolver FIRST (`roleHomePath` -> `/salons/home` and its
/// own nested redirect), which itself reads `mySalonsProvider` as part of
/// deciding where an owner with a resolved single salon should land — so by
/// the time this file's own `router.go(target)` runs, a same-microtask-
/// resolving stub has ALREADY settled, and `salonManageGuard`'s owner arm
/// sees a genuinely resolved (non-matching) list and BOUNCES the navigation
/// before `_SalonManageServicesListRoute`/`_SalonManageServiceEditRoute` ever
/// mount — the opposite of what this file needs to prove. A `Completer` that
/// is NEVER completed keeps `mySalonsProvider` in `AsyncLoading` for the
/// whole test, so the guard takes its documented fallback and the navigation
/// actually reaches the route — and `canManageSalonProvider`'s owner arm
/// (`mySalons is! AsyncData<List<Salon>> -> false`) independently, correctly
/// refuses to treat "unresolved" as "safe to write", which is the whole
/// point of Phase 322's defense-in-depth.
class _UnresolvedMySalons extends MySalons {
  @override
  Future<List<Salon>> build() => Completer<List<Salon>>().future;
}

class _MockDio extends Mock implements Dio {}

class _MockServiceApi extends Mock implements ServiceControllerApi {}

class _MockCategoryApi extends Mock implements CategoryRequestControllerApi {}

class _MockCatalogApi extends Mock implements ServiceCatalogControllerApi {}

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
  late _MockDio mockDio;
  late _MockServiceApi mockServiceApi;
  late _MockCategoryApi mockCategoryApi;
  late _MockCatalogApi mockCatalogApi;
  late List<Map<String, Object?>> salonRows;

  setUp(() {
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    _MutableAuthNotifier.seed = _kAdminSameSalon;
    salonRows = <Map<String, Object?>>[
      _serviceRow(assignmentId: 'svc-1', defId: 'def-1', name: 'Манікюр'),
    ];

    mockDio = _MockDio();
    mockServiceApi = _MockServiceApi();
    mockCategoryApi = _MockCategoryApi();
    mockCatalogApi = _MockCatalogApi();

    when(() => mockDio.get<Object?>(any())).thenAnswer((invocation) async {
      final String path = invocation.positionalArguments[0] as String;
      return Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, Object?>{'success': true, 'data': salonRows},
      );
    });
  });

  tearDown(AppStartTime.resetForTest);

  ProviderContainer makeContainer({List<dynamic> extraOverrides = const []}) {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authProvider.overrideWith(_MutableAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        salonManagementProfileProvider.overrideWith(_StubRoster.new),
        dioProvider.overrideWithValue(mockDio),
        serviceApiProvider.overrideWithValue(mockServiceApi),
        categoryRequestApiProvider.overrideWithValue(mockCategoryApi),
        serviceCatalogApiProvider.overrideWithValue(mockCatalogApi),
        approvedCategoriesProvider.overrideWith(
          (_) async => const <ServiceCategoryOption>[],
        ),
        // ignore: avoid_dynamic_calls
        ...extraOverrides.cast(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<GoRouter> pumpRouter(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final GoRouter router = container.read(appRouterProvider);
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

  Finder countHeader() => find.byKey(const Key('services_count_header'));

  // -------------------------------------------------------------------------
  // LIST leaf — `_SalonManageServicesListRoute`.
  // -------------------------------------------------------------------------

  testWidgets(
    'TRUE — a SALON_ADMIN of THIS salon sees the FAB, and screen.writable '
    'is true',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntilFound(tester, countHeader());

      expect(
        countHeader(),
        findsOneWidget,
        reason: 'positive pairing — the list itself rendered',
      );
      expect(
        find.byKey(const Key('btn-create-service')),
        findsOneWidget,
        reason: 'canManageSalonProvider(salonId) == true for this admin',
      );
      expect(
        tester
            .widget<ServicesListScreen>(find.byType(ServicesListScreen))
            .writable,
        isTrue,
      );
    },
  );

  testWidgets('FALSE — a SALON_OWNER admitted via the guard\'s cold-deep-link '
      'fallback (mySalonsProvider still UNRESOLVED) has no FAB, while the '
      'list itself keeps rendering', (tester) async {
    _MutableAuthNotifier.seed = _kOwner;
    final container = makeContainer(
      extraOverrides: [mySalonsProvider.overrideWith(_UnresolvedMySalons.new)],
    );
    final router = await pumpRouter(tester, container);

    router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
    await pumpUntilFound(tester, countHeader());

    expect(
      countHeader(),
      findsOneWidget,
      reason:
          'positive pairing — the route was reached and the list '
          'rendered; only the WRITE affordance must be gone, not the '
          'screen',
    );
    expect(
      find.byKey(const Key('btn-create-service')),
      findsNothing,
      reason:
          'canManageSalonProvider(salonId) == false — mySalonsProvider is '
          'not a settled AsyncData, so ownership of salon-S is NOT proven',
    );
    expect(
      tester
          .widget<ServicesListScreen>(find.byType(ServicesListScreen))
          .writable,
      isFalse,
    );
  });

  // -------------------------------------------------------------------------
  // EDIT leaf — `_SalonManageServiceEditRoute`.
  // -------------------------------------------------------------------------

  testWidgets(
    'TRUE — a SALON_ADMIN of THIS salon sees the delete affordance on the '
    'edit leaf, and screen.writable is true',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(
        RouteNames.salonManageStaffServiceEdit(
          _kSalonId,
          _kMemberUserId,
          'svc-1',
        ),
      );
      await pumpUntilFound(tester, find.byType(ServiceEditScreen));
      await pumpUntilFound(
        tester,
        find.byKey(const Key('service-edit-form-svc-1')),
      );

      expect(
        find.byKey(const Key('service-edit-form-svc-1')),
        findsOneWidget,
        reason: 'positive pairing — the edit form itself rendered',
      );
      expect(
        find.byKey(const Key('btn-delete-service')),
        findsOneWidget,
        reason: 'canManageSalonProvider(salonId) == true for this admin',
      );
      expect(
        tester
            .widget<ServiceEditScreen>(find.byType(ServiceEditScreen))
            .writable,
        isTrue,
      );
    },
  );

  testWidgets('FALSE — a SALON_OWNER admitted via the guard\'s cold-deep-link '
      'fallback (mySalonsProvider still UNRESOLVED) has no delete affordance '
      'on the edit leaf, while the form itself keeps rendering', (
    tester,
  ) async {
    _MutableAuthNotifier.seed = _kOwner;
    final container = makeContainer(
      extraOverrides: [mySalonsProvider.overrideWith(_UnresolvedMySalons.new)],
    );
    final router = await pumpRouter(tester, container);

    router.go(
      RouteNames.salonManageStaffServiceEdit(
        _kSalonId,
        _kMemberUserId,
        'svc-1',
      ),
    );
    await pumpUntilFound(tester, find.byType(ServiceEditScreen));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-svc-1')),
    );

    expect(
      find.byKey(const Key('service-edit-form-svc-1')),
      findsOneWidget,
      reason:
          'positive pairing — the form itself must still render; only '
          'the WRITE affordance is gone',
    );
    expect(
      find.byKey(const Key('btn-delete-service')),
      findsNothing,
      reason:
          'canManageSalonProvider(salonId) == false — mySalonsProvider is '
          'not a settled AsyncData, so ownership of salon-S is NOT proven',
    );
    expect(
      tester.widget<ServiceEditScreen>(find.byType(ServiceEditScreen)).writable,
      isFalse,
    );
  });
}
