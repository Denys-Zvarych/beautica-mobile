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
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart'
    show MasterType;
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/services/application/owner_performed_services_provider.dart';
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
import '../helpers/test_container.dart';

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
  /// The roster row under test — [_kMasterEntry] unless a Phase 371 case
  /// swaps in the owner's row.
  static SalonStaffMember entry = _kMasterEntry;

  /// Extra roster rows (the real-chain identity-lock cases add the owner's
  /// row beside [entry]).
  static List<SalonStaffMember> extra = const <SalonStaffMember>[];

  @override
  Future<SalonManagementProfileData> build(String salonId) async => (
    const Salon(id: _kSalonId, name: 'Салон'),
    <SalonStaffMember>[entry, ...extra],
  );
}

/// A SETTLED `mySalonsProvider` containing [_kSalonId] — the owner who
/// provably owns this salon (Phase 371 owner-writable case).
class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: _kSalonId, name: 'Салон'),
  ];
}

/// The salon owner's own master row (Phase 371) — same ids as
/// [_kMasterEntry] so the routes resolve it, `masterType: salonOwner`.
const SalonStaffMember _kOwnerRow = SalonStaffMember(
  userId: _kMemberUserId,
  masterId: _kMasterRowId,
  role: SalonStaffRole.master,
  masterType: MasterType.salonOwner,
  firstName: 'Власник',
  lastName: 'Салону',
);

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

/// A `mySalonsProvider` the test RELEASES by hand — the cold-window driver:
/// pending until [release] runs, then settled to [_kSalonId].
class _GatedMySalons extends MySalons {
  static Completer<List<Salon>> gate = Completer<List<Salon>>();

  static void release() =>
      gate.complete(const <Salon>[Salon(id: _kSalonId, name: 'Салон')]);

  @override
  Future<List<Salon>> build() => gate.future;
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
    _StubRoster.entry = _kMasterEntry;
    _StubRoster.extra = const <SalonStaffMember>[];
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
    final container = makeTestContainer(
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
        ...extraOverrides.cast<Object>(),
      ],
    );
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

  testWidgets(
    'PENDING — a SALON_OWNER admitted via the guard\'s cold-deep-link '
    'fallback (mySalonsProvider still UNRESOLVED) sees the loading '
    'placeholder, never a read-only list (no FAB, no ServicesListScreen)',
    (tester) async {
      _MutableAuthNotifier.seed = _kOwner;
      final container = makeContainer(
        extraOverrides: [
          mySalonsProvider.overrideWith(_UnresolvedMySalons.new),
        ],
      );
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntilFound(
        tester,
        find.byKey(const Key('salon_manage_services_pending')),
      );

      expect(
        find.byKey(const Key('salon_manage_services_pending')),
        findsOneWidget,
        reason: 'cycle 3 — pending is "not known yet", not a read-only verdict',
      );
      expect(find.byType(ServicesListScreen), findsNothing);
      expect(find.byKey(const Key('btn-create-service')), findsNothing);
    },
  );

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

  testWidgets('PENDING — a SALON_OWNER on the cold-deep-link fallback sees the '
      'loading placeholder on the edit leaf, never a read-only form', (
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
    await pumpUntilFound(
      tester,
      find.byKey(const Key('salon_manage_service_edit_pending')),
    );

    expect(
      find.byKey(const Key('salon_manage_service_edit_pending')),
      findsOneWidget,
    );
    expect(find.byType(ServiceEditScreen), findsNothing);
    expect(find.byKey(const Key('btn-delete-service')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Phase 371 (377 §1) — the OWNER's row is owner-only: an admin deep link
  // gets a read-only list / form and no bulk-setup form. Owner → writable;
  // admin on a normal master → writable (the TRUE cases above).
  // -------------------------------------------------------------------------

  testWidgets('admin deep link to the OWNER\'s services list → read-only: '
      'no FAB, no per-row edit (onEdit == null path), list still renders', (
    tester,
  ) async {
    _StubRoster.entry = _kOwnerRow;
    final container = makeContainer();
    final router = await pumpRouter(tester, container);

    router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
    await pumpUntilFound(tester, countHeader());

    expect(countHeader(), findsOneWidget);
    expect(find.byKey(const Key('btn-create-service')), findsNothing);
    expect(
      tester
          .widget<ServicesListScreen>(find.byType(ServicesListScreen))
          .writable,
      isFalse,
    );
  });

  testWidgets('admin deep link to the OWNER\'s services/setup → the bulk form '
      'is never shown; lands on the read-only list', (tester) async {
    _StubRoster.entry = _kOwnerRow;
    final container = makeContainer();
    final router = await pumpRouter(tester, container);

    router.go(
      RouteNames.salonManageStaffServiceSetup(_kSalonId, _kMemberUserId),
    );
    await pumpUntilFound(tester, countHeader());

    expect(find.byType(ServiceSetupScreen), findsNothing);
    expect(
      tester
          .widget<ServicesListScreen>(find.byType(ServicesListScreen))
          .writable,
      isFalse,
    );
  });

  testWidgets('admin deep link to the OWNER\'s service edit → read-only form '
      '(no delete)', (tester) async {
    _StubRoster.entry = _kOwnerRow;
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

    expect(find.byKey(const Key('btn-delete-service')), findsNothing);
    expect(
      tester.widget<ServiceEditScreen>(find.byType(ServiceEditScreen)).writable,
      isFalse,
    );
  });

  testWidgets('the OWNER (settled mySalons) on their own row → list and edit '
      'stay writable', (tester) async {
    _MutableAuthNotifier.seed = _kOwner;
    _StubRoster.entry = _kOwnerRow;
    final container = makeContainer(
      extraOverrides: [mySalonsProvider.overrideWith(_SettledMySalons.new)],
    );
    await container.read(mySalonsProvider.future);
    final router = await pumpRouter(tester, container);

    router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
    await pumpUntilFound(tester, countHeader());

    expect(find.byKey(const Key('btn-create-service')), findsOneWidget);
    expect(
      tester
          .widget<ServicesListScreen>(find.byType(ServicesListScreen))
          .writable,
      isTrue,
    );
  });

  testWidgets('setup pushed from a DIFFERENT page (the edit form) still lands '
      "on the owner's read-only list, and the page beneath stays intact", (
    tester,
  ) async {
    _StubRoster.entry = _kOwnerRow;
    final container = makeContainer();
    final router = await pumpRouter(tester, container);

    router.go(
      RouteNames.salonManageStaffServiceEdit(
        _kSalonId,
        _kMemberUserId,
        'svc-1',
      ),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-svc-1')),
    );

    unawaited(
      router.push(
        RouteNames.salonManageStaffServiceSetup(_kSalonId, _kMemberUserId),
      ),
    );
    await pumpUntilFound(tester, countHeader());

    expect(find.byType(ServiceSetupScreen), findsNothing);
    expect(
      tester
          .widget<ServicesListScreen>(find.byType(ServicesListScreen))
          .writable,
      isFalse,
    );

    // Back-stack sanity: popping the list reveals the page setup was pushed
    // from — the redirect replaced only the setup screen.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ServicesListScreen), findsNothing);
    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
  });

  testWidgets('mismatched member/service edit link (a serviceId that is not '
      "this member's) → error state: no form, no save, no delete", (
    tester,
  ) async {
    // The member under test is a normal master; `salonRows` is THEIR
    // catalogue. 'svc-owner-only' belongs to someone else (the owner).
    final container = makeContainer();
    final router = await pumpRouter(tester, container);

    router.go(
      RouteNames.salonManageStaffServiceEdit(
        _kSalonId,
        _kMemberUserId,
        'svc-owner-only',
      ),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service_edit_error_state')),
    );

    expect(
      find.byKey(const Key('service_edit_error_state')),
      findsOneWidget,
      reason: 'positive: the not-found error state, not a stuck spinner',
    );
    expect(
      find.byKey(const Key('service-edit-form-svc-owner-only')),
      findsNothing,
    );
    expect(find.byKey(const Key('btn-delete-service')), findsNothing);
    expect(find.byKey(const Key('btn-submit-service')), findsNothing);

    // Positive pairing: the SAME link with a serviceId that IS the member's
    // renders the form.
    router.go(
      RouteNames.salonManageStaffServiceEdit(
        _kSalonId,
        _kMemberUserId,
        'svc-1',
      ),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-svc-1')),
    );
  });

  // -------------------------------------------------------------------------
  // Phase 377 (24.4) — identityLocked on the edit leaf.
  // -------------------------------------------------------------------------

  Future<void> openEditLeaf(WidgetTester tester, GoRouter router) async {
    router.go(
      RouteNames.salonManageStaffServiceEdit(
        _kSalonId,
        _kMemberUserId,
        'svc-1',
      ),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-svc-1')),
    );
  }

  ServiceEditScreen editScreen(WidgetTester tester) =>
      tester.widget<ServiceEditScreen>(find.byType(ServiceEditScreen));

  final Finder hint = find.byKey(
    const Key('service-edit-identity-locked-hint'),
  );

  testWidgets('admin on a NON-owner master\'s service the owner also performs '
      '-> identityLocked true, hint shown, still writable', (tester) async {
    final container = makeContainer(
      extraOverrides: [
        serviceIdentityLockProvider(
          _kSalonId,
          'def-1',
        ).overrideWithValue(ServiceIdentityLock.locked),
      ],
    );
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);

    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(editScreen(tester).identityLocked, isTrue);
    expect(editScreen(tester).writable, isTrue);
    expect(hint, findsOneWidget);
    expect(find.byKey(const Key('btn-submit-service')), findsOneWidget);
    expect(find.byKey(const Key('btn-delete-service')), findsOneWidget);
  });

  testWidgets('a service the owner does NOT perform -> identityLocked false, '
      'no hint', (tester) async {
    final container = makeContainer(
      extraOverrides: [
        serviceIdentityLockProvider(
          _kSalonId,
          'def-1',
        ).overrideWithValue(ServiceIdentityLock.unlocked),
      ],
    );
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);

    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(editScreen(tester).identityLocked, isFalse);
    expect(hint, findsNothing);
  });

  testWidgets('the OWNER viewer on a service the owner performs -> '
      'identityLocked false (salon-scoped viewerOwnsSalon)', (tester) async {
    _MutableAuthNotifier.seed = _kOwner;
    _StubRoster.extra = const <SalonStaffMember>[
      SalonStaffMember(
        userId: 'user-owner',
        masterId: 'master-owner',
        role: SalonStaffRole.master,
        masterType: MasterType.salonOwner,
        firstName: 'Власник',
        lastName: 'Салону',
      ),
    ];
    final container = makeContainer(
      extraOverrides: [
        mySalonsProvider.overrideWith(_SettledMySalons.new),
        ownerMasterServiceDefIdsProvider(
          'master-owner',
        ).overrideWith((_) async => const <String>{'def-1'}),
      ],
    );
    await container.read(mySalonsProvider.future);
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);

    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(editScreen(tester).identityLocked, isFalse);
    expect(editScreen(tester).writable, isTrue);
    expect(hint, findsNothing);
  });

  testWidgets('admin on the OWNER\'s own row (fully read-only) wins over '
      'identityLocked: no hint, no save', (tester) async {
    _StubRoster.entry = _kOwnerRow;
    final container = makeContainer(
      extraOverrides: [
        serviceIdentityLockProvider(
          _kSalonId,
          'def-1',
        ).overrideWithValue(ServiceIdentityLock.locked),
      ],
    );
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);

    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(editScreen(tester).writable, isFalse);
    expect(hint, findsNothing);
    expect(find.byKey(const Key('btn-submit-service')), findsNothing);
  });

  // Audit-fix 1 — the REAL derived chain (roster + owner catalogue), with the
  // owner catalogue gated by hand.
  const SalonStaffMember ownerRowElsewhere = SalonStaffMember(
    userId: 'user-owner',
    masterId: 'master-owner',
    role: SalonStaffRole.master,
    masterType: MasterType.salonOwner,
    firstName: 'Власник',
    lastName: 'Салону',
  );

  testWidgets('admin with the owner set still PENDING -> loading scaffold, '
      'NO form; once it resolves the form is locked', (tester) async {
    _StubRoster.extra = const <SalonStaffMember>[ownerRowElsewhere];
    // Created INSIDE the test body so it lives in the FakeAsync zone.
    final Completer<Set<String>> gate = Completer<Set<String>>();
    final container = makeContainer(
      extraOverrides: [
        ownerMasterServiceDefIdsProvider(
          'master-owner',
        ).overrideWith((_) => gate.future),
      ],
    );
    final router = await pumpRouter(tester, container);

    router.go(
      RouteNames.salonManageStaffServiceEdit(
        _kSalonId,
        _kMemberUserId,
        'svc-1',
      ),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('salon_manage_service_edit_identity_pending')),
    );

    expect(
      find.byKey(const Key('salon_manage_service_edit_identity_pending')),
      findsOneWidget,
      reason: 'positive pairing for the absence asserts below',
    );
    expect(find.byType(ServiceEditScreen), findsNothing);
    expect(find.byKey(const Key('service-edit-form-svc-1')), findsNothing);

    gate.complete(<String>{'def-1'});
    await pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-svc-1')),
    );

    expect(editScreen(tester).identityLocked, isTrue);
    expect(hint, findsOneWidget);
    expect(
      find.byKey(const Key('salon_manage_service_edit_identity_pending')),
      findsNothing,
    );
  });

  testWidgets('REAL chain — admin, owner performs def-1 -> identityLocked '
      'true (verdict computed from roster + owner catalogue)', (tester) async {
    _StubRoster.extra = const <SalonStaffMember>[ownerRowElsewhere];
    final container = makeContainer(
      extraOverrides: [
        ownerMasterServiceDefIdsProvider(
          'master-owner',
        ).overrideWith((_) async => const <String>{'def-1'}),
      ],
    );
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);

    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(editScreen(tester).identityLocked, isTrue);
    expect(hint, findsOneWidget);
  });

  testWidgets('REAL chain — admin, owner performs only another def -> '
      'identityLocked false', (tester) async {
    _StubRoster.extra = const <SalonStaffMember>[ownerRowElsewhere];
    final container = makeContainer(
      extraOverrides: [
        ownerMasterServiceDefIdsProvider(
          'master-owner',
        ).overrideWith((_) async => const <String>{'def-other'}),
      ],
    );
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);

    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(editScreen(tester).identityLocked, isFalse);
    expect(hint, findsNothing);
  });

  testWidgets('a mid-edit owner-catalogue REFRESH keeps the form mounted and '
      'the typed text intact (never the loading scaffold)', (tester) async {
    _StubRoster.extra = const <SalonStaffMember>[ownerRowElsewhere];
    // Created INSIDE the test body so it lives in the FakeAsync zone.
    final Completer<Set<String>> refresh = Completer<Set<String>>();
    int calls = 0;
    final container = makeContainer(
      extraOverrides: [
        ownerMasterServiceDefIdsProvider('master-owner').overrideWith((_) {
          calls++;
          return calls == 1
              ? Future<Set<String>>.value(const <String>{'def-other'})
              : refresh.future;
        }),
      ],
    );
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);
    // Keep the autoDispose owner-catalogue provider alive across the refresh.
    final sub = container.listen(
      serviceIdentityLockProvider(_kSalonId, 'def-1'),
      (_, _) {},
    );
    addTearDown(sub.close);

    final Finder nameField = find.descendant(
      of: find.byKey(const Key('field-service-name')),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField, 'Набрана назва');
    await tester.pump();

    container.invalidate(ownerMasterServiceDefIdsProvider('master-owner'));
    await tester.pump();
    await tester.pump();

    expect(calls, 2, reason: 'positive: the refresh really started');
    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(
      find.byKey(const Key('salon_manage_service_edit_identity_pending')),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(nameField).controller?.text,
      'Набрана назва',
    );
  });

  testWidgets('owner catalogue read ERRORS -> fail-open: form shown, not '
      'locked', (tester) async {
    _StubRoster.extra = const <SalonStaffMember>[ownerRowElsewhere];
    final container = makeContainer(
      extraOverrides: [
        ownerMasterServiceDefIdsProvider(
          'master-owner',
        ).overrideWith((_) async => throw const NotFoundFailure()),
      ],
    );
    final router = await pumpRouter(tester, container);
    await openEditLeaf(tester, router);

    expect(find.byKey(const Key('service-edit-form-svc-1')), findsOneWidget);
    expect(editScreen(tester).identityLocked, isFalse);
  });

  testWidgets('cold owner at /services/setup on their OWN row: skeleton while '
      'mySalons is pending, NO redirect; once it resolves the bulk form '
      'appears', (tester) async {
    _MutableAuthNotifier.seed = _kOwner;
    _StubRoster.entry = _kOwnerRow;
    // Created INSIDE the test body so it lives in the FakeAsync zone — a
    // setUp-created Completer's microtasks would never flush on tester.pump.
    _GatedMySalons.gate = Completer<List<Salon>>();
    final container = makeContainer(
      extraOverrides: [mySalonsProvider.overrideWith(_GatedMySalons.new)],
    );
    final router = await pumpRouter(tester, container);

    router.go(
      RouteNames.salonManageStaffServiceSetup(_kSalonId, _kMemberUserId),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('salon_manage_service_setup_loading')),
    );
    // fixed-wait-ok: absence proof — gives a would-be post-frame redirect
    // time to fire; there is no condition to pump until for a non-event.
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('salon_manage_service_setup_loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('salon_manage_service_setup_redirect')),
      findsNothing,
    );
    expect(find.byType(ServicesListScreen), findsNothing);
    expect(find.byType(ServiceSetupScreen), findsNothing);

    _GatedMySalons.release();
    await pumpUntilFound(tester, find.byType(ServiceSetupScreen));
    expect(find.byType(ServiceSetupScreen), findsOneWidget);
    expect(find.byType(ServicesListScreen), findsNothing);
  });
}
