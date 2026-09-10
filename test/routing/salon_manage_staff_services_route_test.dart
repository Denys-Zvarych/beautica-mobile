// Phase 317 — route-level tests for the salon-target services subtree:
// `/salons/:salonId/manage/staff/:memberId/services`, `…/services/setup` and
// `…/services/:serviceId/edit`.
//
// WHAT THIS FILE PINS, and why each case cannot pass vacuously
// ------------------------------------------------------------
//   1. TRANSITIVITY — the `dependencies:` cascade (D2's forced option (a))
//      actually reaches the repository. Asserted on the URI the repository
//      EMITS (`/api/v1/salons/S/masters/M/services`), never on
//      `HttpServiceRepository.target`: a field read stays green on a
//      repository nothing consumes
//      (`project_widget_field_assertion_is_vacuous`).
//   2. DIFFERING IDS — the fixture's roster `userId` ('user-U') and `masters`
//      row id ('master-M') are DIFFERENT strings, and the emitted path is
//      asserted to contain the master row id AND `isNot(contains(userId))`.
//      With equal ids the whole D4 resolution would be untested
//      (`project_fixture_values_can_defang_assertions`).
//   3. ONE SCOPE, NOT THREE (D2) — navigate list → edit inside the subtree,
//      delete, and assert the LIST RE-RENDERS WITHOUT the deleted row.
//      Deliberately NOT `identical(providerA, providerB)`, which passes on a
//      screen that never repaints.
//   4. SCOPE UNWINDS ON POP (D2) — open master M1, pop to the roster, open
//      M2; assert a request for M2 was actually made (count ≥ 1), not merely
//      that no M1 request appeared (which an all-failing fixture satisfies).
//   5. `/masters//` NEVER REACHES THE WIRE (D4) — while the roster is still
//      loading, no request with an empty master segment is emitted; paired
//      with `recordedUris, isNotEmpty` once it resolves, so a fixture that
//      emits nothing at all cannot pass.
//   6. RELEASE-MODE SILENCE — riverpod's "may be scoped" assert is
//      `kDebugMode`-only (`riverpod-3.1.0/.../element.dart:922`) and
//      `riverpod_lint` was removed on 2026-08-18, so a missed `dependencies:`
//      declaration ships silently. Each of the FIVE reachable providers gets
//      its OWN named assertion that it resolves to a SCOPED element inside the
//      subtree — never a loop over a list that could be empty.
//   7. AUTH BOUNDARY SURVIVES SCOPING — an identity change inside the salon
//      scope rebuilds the repository AND emits a fresh request.
//   8. PAGE TYPE, NEVER LOCATION STRING — go_router's literal-before-dynamic
//      shadowing makes a location assertion pass while a different page
//      builds, and the `setup` literal is a PEER of the `:serviceId` capture
//      here, so the trap is live (`project_gorouter_literal_before_dynamic_
//      shadowing`).
//
// MECHANISM (reused, not invented — REUSE-FIRST): mirrors
// `salon_manage_staff_schedule_route_test.dart`, the phase-312 sibling that
// pins the neighbouring `/schedule` subtree — mount the REAL
// `appRouterProvider` through an `UncontrolledProviderScope`, drive
// `router.go(...)`, and observe the ACTUAL request the repository makes.
//
// ROLE ADMISSION for these three paths (stated explicitly because the router's
// role lists and the backend's `@PreAuthorize` lists are independently
// maintained with no shared source of truth): SALON_OWNER and SALON_ADMIN of
// the salon are ADMITTED; SALON_MASTER, INDEPENDENT_MASTER and CLIENT are each
// bounced to their own `roleHomePath`; an unauthenticated visitor is sent to
// `/login` by the global `authRedirect`. The behavioural matrix lives in
// `salon_manage_route_guard_test.dart` alongside every other route in this
// subtree; this file uses a SALON_ADMIN of the salon throughout.

import 'dart:async';

import 'package:beautica_api/beautica_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
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
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_target.dart';
import 'package:beautica_mobile/features/services/presentation/service_by_id_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';
import '../helpers/velvet_snack_matchers.dart';

// ---------------------------------------------------------------------------
// Fixtures — the userId and the masters ROW id are DELIBERATELY different.
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-S';

/// The roster entry's `userId` — what the `:memberId` path segment carries.
const String _kMemberUserId = 'user-U';

/// The `masters` ROW id the route builder must resolve from [_kMemberUserId].
/// Shares NO substring with it, so `isNot(contains(_kMemberUserId))` is a
/// real assertion rather than an accident of the fixture.
const String _kMasterRowId = 'master-M';

/// A SECOND roster master, for the scope-unwind case.
const String _kMember2UserId = 'user-U2';
const String _kMaster2RowId = 'master-M2';

/// An ADMIN roster entry — `masterId` is null by contract, so D4's error gate
/// is what must render.
const String _kAdminMemberUserId = 'user-A';

const User _kAdmin = User(
  id: 'admin-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Тест',
  lastName: 'Адмін',
  salonId: _kSalonId,
);

const User _kOtherAdmin = User(
  id: 'admin-2',
  email: 'admin2@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Інший',
  lastName: 'Адмін',
  salonId: _kSalonId,
);

const SalonStaffMember _kMasterEntry = SalonStaffMember(
  userId: _kMemberUserId,
  masterId: _kMasterRowId,
  role: SalonStaffRole.master,
  firstName: 'Майстер',
  lastName: 'Один',
);

const SalonStaffMember _kMaster2Entry = SalonStaffMember(
  userId: _kMember2UserId,
  masterId: _kMaster2RowId,
  role: SalonStaffRole.master,
  firstName: 'Майстер',
  lastName: 'Два',
);

const SalonStaffMember _kAdminEntry = SalonStaffMember(
  userId: _kAdminMemberUserId,
  role: SalonStaffRole.admin,
  firstName: 'Адмін',
  lastName: 'Ростер',
);

const List<SalonStaffMember> _kRoster = <SalonStaffMember>[
  _kMasterEntry,
  _kMaster2Entry,
  _kAdminEntry,
];

/// One service row in the salon-master list response, in the wire shape
/// `MasterServiceMapper.fromDto` consumes.
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
  static User seed = _kAdmin;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: seed, accessToken: 'tok');

  void signInAs(User user) {
    state = AsyncData<AuthSession>(
      AuthSession.authenticated(user: user, accessToken: 'tok-2'),
    );
  }
}

/// Roster that resolves on demand, so the D4 loading gate can be observed.
class _ControlledRoster extends SalonManagementProfile {
  /// When non-null, `build` awaits it — the test completes it to resolve.
  static Completer<void>? gate;

  /// When true, `build` THROWS instead of resolving — the cycle-2 item A
  /// case: the roster reloads and the reload FAILS after a successful load.
  static bool failNext = false;

  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    // Mirrors the REAL notifier's first line
    // (`salon_management_profile_notifier.dart:155`) — the identity watch that
    // evicts one signed-in user's roster on the auth boundary. Reproduced here
    // because it is this family's ONLY dependency edge, and therefore the only
    // thing that can put it into a genuine RELOAD (as opposed to the REFRESH
    // an `invalidate` produces, which `when` already skips by default via
    // `skipLoadingOnRefresh: true`). The audit F3 reload case is driven
    // through it.
    ref.watch(authProvider.select(authUserIdOrNull));
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    // Non-retryable by `failure_retry_policy.dart:229`, so the error state is
    // reached ONCE and deterministically — a retryable failure would cycle
    // through `AsyncLoading(retrying: true)` and make the assertion race.
    if (failNext) throw const UnauthorizedFailure();
    return (const Salon(id: _kSalonId, name: 'Салон'), _kRoster);
  }
}

class _StubMasterProfile extends MasterProfile {
  /// How many times `GET /masters/me` would have been issued. Counted rather
  /// than mocked on Dio because `masterProfileProvider` is overridden here —
  /// the observable is "was this provider BUILT at all", which is exactly the
  /// question the audit F1 fix answers.
  static int builds = 0;

  @override
  Future<Master> build() async {
    builds++;
    return const Master(
      id: 'operator-master-row',
      firstName: 'Оператор',
      lastName: 'Салону',
      reviewCount: 0,
      type: MasterType.independentMaster,
    );
  }
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

  /// Every URI the RAW Dio was asked for, in order — the observation surface
  /// for every path assertion in this file.
  late List<String> recordedUris;

  /// The rows the salon-master list endpoint currently returns. Mutable so a
  /// delete can be reflected on the next fetch.
  late List<Map<String, Object?>> salonRows;

  setUp(() {
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    _MutableAuthNotifier.seed = _kAdmin;
    _ControlledRoster.gate = null;
    _ControlledRoster.failNext = false;
    _StubMasterProfile.builds = 0;
    recordedUris = <String>[];
    salonRows = <Map<String, Object?>>[
      _serviceRow(assignmentId: 'svc-1', defId: 'def-1', name: 'Манікюр'),
      _serviceRow(assignmentId: 'svc-2', defId: 'def-2', name: 'Педикюр'),
    ];

    mockDio = _MockDio();
    mockServiceApi = _MockServiceApi();
    mockCategoryApi = _MockCategoryApi();
    mockCatalogApi = _MockCatalogApi();

    when(() => mockDio.get<Object?>(any())).thenAnswer((invocation) async {
      final String path = invocation.positionalArguments[0] as String;
      recordedUris.add(path);
      return Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, Object?>{'success': true, 'data': salonRows},
      );
    });
    when(() => mockDio.delete<Object?>(any())).thenAnswer((invocation) async {
      final String path = invocation.positionalArguments[0] as String;
      recordedUris.add('DELETE $path');
      // Reflect the unassign so the list's re-fetch can prove it refreshed.
      salonRows = salonRows
          .where(
            (row) =>
                (row['serviceDefinition']! as Map<String, Object?>)['id'] !=
                'def-1',
          )
          .toList();
      return Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: 204,
      );
    });

    // The OWNER endpoint: stubbed so a root-resolved repository would succeed
    // silently rather than throw. That is deliberate — the failure mode this
    // file guards is a repository that resolves to ROOT and quietly lists the
    // OPERATOR's own catalogue, and a fixture that made that path throw would
    // turn a wrong-tenant bug into an unrelated error.
    when(() => mockServiceApi.getMyServices()).thenAnswer(
      (_) async => Response(
        data:
            (ApiResponseListMasterServiceResponseBuilder()
                  ..success = true
                  ..data = ListBuilder<MasterServiceResponse>())
                .build(),
        statusCode: 200,
        requestOptions: RequestOptions(
          path: '/api/v1/independent-masters/me/services',
        ),
      ),
    );
  });

  tearDown(AppStartTime.resetForTest);

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authProvider.overrideWith(_MutableAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        salonManagementProfileProvider.overrideWith(_ControlledRoster.new),
        masterProfileProvider.overrideWith(_StubMasterProfile.new),
        // The roster entry's own services read (`salonStaffMemberProfile`)
        // goes through the PUBLIC repository, which is a different seam from
        // the one under test — faked so it never touches Dio.
        publicServiceRepositoryProvider.overrideWithValue(
          FakeServiceRepository(),
        ),
        dioProvider.overrideWithValue(mockDio),
        serviceApiProvider.overrideWithValue(mockServiceApi),
        categoryRequestApiProvider.overrideWithValue(mockCategoryApi),
        serviceCatalogApiProvider.overrideWithValue(mockCatalogApi),
        // Overridden DIRECTLY, not through the repository: this provider
        // sources `categoryRequestApiProvider` itself
        // (`project_approved_categories_provider_override_footgun`).
        approvedCategoriesProvider.overrideWith(
          (_) async => const <ServiceCategoryOption>[],
        ),
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
    // Let `authProvider` genuinely settle BEFORE navigating — a `go` issued
    // while the session is unresolved can be re-redirected out from under it
    // (the precedent `salon_manage_staff_schedule_route_test.dart` documents).
    await container.read(authProvider.future);
    await tester.pump();
    return router;
  }

  /// Pumps until [condition] holds or the budget runs out.
  Future<void> pumpWhile(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 60; i++) {
      if (condition()) return;
      // fixed-wait-ok: this IS pump-until — the loop exits the instant the
      // condition holds; 50 ms is only the polling step, not a guessed total.
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps until [finder] has a match or the budget runs out.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) =>
      pumpWhile(tester, () => finder.evaluate().isNotEmpty);

  /// Pumps until [key] names an ENABLED [IconButton] that is actually
  /// hit-testable. Both halves matter: the delete control is disabled while
  /// `serviceByIdProvider` resolves, and the page-transition slide leaves it
  /// off-screen for the first frames. Fixing the finder is the required
  /// remedy — never `warnIfMissed: false`
  /// (`project_animatedscale_root_breaks_tap_by_key`).
  Future<void> pumpUntilTappableIconButton(WidgetTester tester, Key key) async {
    final Finder finder = find.byKey(key);
    await pumpWhile(tester, () {
      final Finder hittable = finder.hitTestable();
      if (hittable.evaluate().isEmpty) return false;
      return tester.widget<IconButton>(finder).onPressed != null;
    });
  }

  String salonServicesUri(String masterId) =>
      '/api/v1/salons/$_kSalonId/masters/$masterId/services';

  /// The list screen's active-count header — the observable that proves the
  /// LIST CONTENT rendered. Deliberately NOT a service NAME: every category
  /// section starts COLLAPSED when `initialExpandCategory` is null (the
  /// default on this route), so a card's name is never in the tree and a
  /// `find.text('Манікюр')` assertion would be permanently false — passing
  /// only where it is used as a pump-until budget, which is exactly the
  /// vacuity this file is written against.
  Finder countHeader(String text) => find.text(text);

  // -------------------------------------------------------------------------
  // 8. PAGE TYPE — never a location string.
  // -------------------------------------------------------------------------

  group('page TYPE resolution (never the location string)', () {
    testWidgets('…/services builds ServicesListScreen', (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, find.byType(ServicesListScreen));

      expect(find.byType(ServicesListScreen), findsOneWidget);
      expect(find.byType(ServiceSetupScreen), findsNothing);
      expect(find.byType(ServiceEditScreen), findsNothing);
    });

    testWidgets(
      '…/services/setup builds ServiceSetupScreen — NOT ServiceEditScreen '
      'with serviceId == "setup" (the literal-before-dynamic trap)',
      (tester) async {
        final container = makeContainer();
        final router = await pumpRouter(tester, container);

        router.go(
          RouteNames.salonManageStaffServiceSetup(_kSalonId, _kMemberUserId),
        );
        await pumpUntil(tester, find.byType(ServiceSetupScreen));

        expect(
          find.byType(ServiceSetupScreen),
          findsOneWidget,
          reason:
              '`/setup` and `/:serviceId` are PEERS at the same segment; if '
              '`/setup` were registered after the capture, go_router would '
              'build the edit screen with serviceId == "setup" while the '
              'location string still read ".../setup"',
        );
        expect(find.byType(ServiceEditScreen), findsNothing);
      },
    );

    testWidgets('…/services/:serviceId/edit builds ServiceEditScreen with '
        'that id', (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(
        RouteNames.salonManageStaffServiceEdit(
          _kSalonId,
          _kMemberUserId,
          'svc-1',
        ),
      );
      await pumpUntil(tester, find.byType(ServiceEditScreen));

      expect(find.byType(ServiceEditScreen), findsOneWidget);
      expect(
        tester.widget<ServiceEditScreen>(find.byType(ServiceEditScreen)).id,
        'svc-1',
      );
      expect(find.byType(ServiceSetupScreen), findsNothing);
    });

    testWidgets(
      'the INDEPENDENT_MASTER routes are untouched — /services still builds '
      'ServicesListScreen with NO salon destinations',
      (tester) async {
        _MutableAuthNotifier.seed = const User(
          id: 'im-1',
          email: 'im@beautica.ua',
          role: UserRole.independentMaster,
          firstName: 'Соло',
          lastName: 'Майстер',
        );
        final container = makeContainer();
        final router = await pumpRouter(tester, container);

        router.go(RouteNames.services);
        await pumpUntil(tester, find.byType(ServicesListScreen));

        final ServicesListScreen screen = tester.widget<ServicesListScreen>(
          find.byType(ServicesListScreen),
        );
        expect(
          screen.setupRoute,
          isNull,
          reason:
              "D3's defaults must be untouched on the root route — null means "
              "today's literal",
        );
        expect(screen.editRouteBuilder, isNull);
        expect(screen.resolvedSetupRoute, RouteNames.serviceSetup);
        expect(screen.resolvedEditRouteBuilder('abc'), '/services/abc/edit');
      },
    );
  });

  // -------------------------------------------------------------------------
  // 1 + 2. TRANSITIVITY and DIFFERING IDS.
  // -------------------------------------------------------------------------

  testWidgets(
    'the repository EMITS /salons/S/masters/M/services — the master ROW id, '
    'never the roster userId',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, countHeader('2 послуги'));

      expect(
        recordedUris,
        contains(salonServicesUri(_kMasterRowId)),
        reason:
            'the `dependencies:` cascade must carry the scoped target all the '
            'way to HttpServiceRepository — asserted on the emitted URI, not '
            'on the `target` field, which stays right even when nothing '
            'consumes the repository',
      );
      for (final String uri in recordedUris) {
        expect(
          uri,
          isNot(contains(_kMemberUserId)),
          reason:
              'the `:memberId` segment is a USER id; a userId on '
              '/salons/{s}/masters/{m}/... yields 404, not 403',
        );
      }
      // Anti-vacuity: the owner endpoint must NOT have been used — that is
      // what a root-resolved repository would have called.
      verifyNever(() => mockServiceApi.getMyServices());
    },
  );

  // -------------------------------------------------------------------------
  // AUDIT F1 — `GET /masters/me` is NEVER fired under a salon target.
  // -------------------------------------------------------------------------

  testWidgets('the scoped repository never resolves masterProfileProvider — no '
      'GET /masters/me under a salon target', (tester) async {
    final container = makeContainer();
    final router = await pumpRouter(tester, container);

    router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
    await pumpUntil(tester, countHeader('2 послуги'));

    // The scoped repository is BUILT (precondition — otherwise the two
    // assertions below are satisfied by a subtree that never rendered).
    final ProviderContainer scoped = ProviderScope.containerOf(
      tester.element(find.byType(ServicesListScreen)),
      listen: false,
    );
    expect(scoped.read(serviceRepositoryProvider), isNotNull);
    expect(recordedUris, contains(salonServicesUri(_kMasterRowId)));

    expect(
      container.exists(masterProfileProvider),
      isFalse,
      reason:
          'masterProfileProvider is keepAlive and lives in the ROOT '
          'container, so an unconditional watch in serviceRepositoryProvider '
          'would have created its element here. Under a SalonMasterTarget '
          '`_masterId` is provably unused — _assertAuthenticated reads only '
          '_sessionUserId and target — and `GET /masters/me` is REFUSED for '
          'a SALON_ADMIN by MasterController @PreAuthorize, so the watch is '
          'a guaranteed 403 retried ~4x by beauticaProviderRetry on every '
          'entry into this subtree (the phase 312 hazard, '
          '`schedule_repository_provider.dart:1-16`).',
    );
    expect(
      _StubMasterProfile.builds,
      0,
      reason:
          'asserted on the BUILD COUNT as well as on element existence: a '
          'future refactor that resolves the provider through a different '
          'handle would keep `exists` honest only by accident',
    );
  });

  testWidgets(
    'the INDEPENDENT_MASTER path is unchanged — masterProfileProvider IS '
    'still resolved when the target is null',
    (tester) async {
      _MutableAuthNotifier.seed = const User(
        id: 'im-1',
        email: 'im@beautica.ua',
        role: UserRole.independentMaster,
        firstName: 'Соло',
        lastName: 'Майстер',
      );
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.services);
      await pumpUntil(tester, find.byType(ServicesListScreen));
      await pumpWhile(tester, () => _StubMasterProfile.builds > 0);

      expect(
        _StubMasterProfile.builds,
        greaterThan(0),
        reason:
            "ANTI-VACUITY for the test above. If F1's conditional ever became "
            'unconditional in the other direction — dropping the watch on the '
            'null-target arm too — `_assertAuthenticated`\'s readiness guard '
            'would lose its only input and the "no GET /masters/me" '
            'assertion would pass for the wrong reason.',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 6. RELEASE-MODE SILENCE — five named per-provider scoping assertions.
  // -------------------------------------------------------------------------

  testWidgets(
    'every provider on the chain resolves to a SCOPED element inside the '
    'subtree (the kDebugMode assert cannot be relied on in release)',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, countHeader('2 послуги'));

      final ProviderContainer scoped = ProviderScope.containerOf(
        tester.element(find.byType(ServicesListScreen)),
        listen: false,
      );
      expect(
        identical(scoped, container),
        isFalse,
        reason: 'precondition — the screen must be inside the shell scope',
      );

      // ONE named assertion per provider. A provider that failed to declare
      // its `dependencies:` would resolve to the ROOT element and hand back
      // the IDENTICAL instance the root container does.
      expect(
        identical(
          scoped.read(serviceRepositoryProvider),
          container.read(serviceRepositoryProvider),
        ),
        isFalse,
        reason: 'serviceRepositoryProvider must be scoped',
      );
      expect(
        identical(
          scoped.read(masterServiceCatalogProvider),
          container.read(masterServiceCatalogProvider),
        ),
        isFalse,
        reason: 'masterServiceCatalogProvider must be scoped',
      );
      expect(
        identical(
          scoped.read(servicesListProvider.notifier),
          container.read(servicesListProvider.notifier),
        ),
        isFalse,
        reason: 'servicesListProvider must be scoped',
      );
      expect(
        identical(
          scoped.read(serviceByIdProvider('svc-1')),
          container.read(serviceByIdProvider('svc-1')),
        ),
        isFalse,
        reason: 'serviceByIdProvider must be scoped',
      );
      expect(
        identical(
          scoped.read(serviceTypesProvider('MANICURE')),
          container.read(serviceTypesProvider('MANICURE')),
        ),
        isFalse,
        reason: 'serviceTypesProvider must be scoped',
      );
      expect(
        identical(
          scoped.read(serviceSetupProvider.notifier),
          container.read(serviceSetupProvider.notifier),
        ),
        isFalse,
        reason: 'serviceSetupProvider must be scoped',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 3. ONE SCOPE, NOT THREE.
  // -------------------------------------------------------------------------

  testWidgets(
    'a delete on the EDIT leaf refreshes the LIST leaf — one ProviderScope '
    'shared by the whole subtree, not three forked chains',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, countHeader('2 послуги'));
      expect(countHeader('2 послуги'), findsOneWidget);
      // Let the entry navigation fully settle BEFORE pushing. The salon
      // role-home resolver reaches its own `/shell` destination through a
      // post-frame `go`, and a push issued while that is still in flight ends
      // up stacked on the resolver's match list instead of the services one —
      // so the later pop lands on `/salons/S/shell` rather than back on the
      // list. Measured, not guessed.
      // fixed-wait-ok: draining an in-flight router redirect, not polling a
      // widget condition.
      await tester.pump(const Duration(seconds: 1));

      // Push (not `go`) so the list stays on the stack underneath — the same
      // imperative shape the card's «Редагувати» uses
      // (`project_gorouter_imperative_match_fullpath`).
      final BuildContext ctx = tester.element(find.byType(ServicesListScreen));
      unawaited(
        ctx.push<void>(
          RouteNames.salonManageStaffServiceEdit(
            _kSalonId,
            _kMemberUserId,
            'svc-1',
          ),
        ),
      );
      await pumpUntilTappableIconButton(
        tester,
        const Key('btn-delete-service'),
      );

      await tester.tap(find.byKey(const Key('btn-delete-service')));
      await tester.pump();
      await pumpUntil(tester, find.byKey(const Key('delete-service-dialog')));
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pump();

      await pumpUntil(tester, find.byType(ServicesListScreen).hitTestable());
      // Give the post-delete invalidation + re-fetch a chance to land.
      await pumpUntil(tester, countHeader('1 послуга'));

      expect(
        recordedUris,
        contains('DELETE ${salonServicesUri(_kMasterRowId)}/def-1'),
        reason:
            'phase 316 — with a salon target the delete must UNASSIGN, never '
            'DELETE /services/{id}, which would destroy a shared definition',
      );
      expect(
        countHeader('1 послуга'),
        findsOneWidget,
        reason:
            'D2 — the invalidation fired from the EDIT leaf must reach the '
            "LIST leaf's keepAlive provider, so the list RE-RENDERS with the "
            'deleted row gone. With three per-route scopes it lands in a '
            'different chain and the list still reads «2 послуги».',
      );
      expect(
        countHeader('2 послуги'),
        findsNothing,
        reason: 'the stale count must be gone, not merely joined',
      );
      expect(
        find.byType(ServicesListScreen),
        findsOneWidget,
        reason:
            'anti-vacuity — the list is still MOUNTED (this is a refresh, not '
            'an unmount, which would satisfy the two assertions above)',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 4. SCOPE UNWINDS ON POP.
  // -------------------------------------------------------------------------

  testWidgets(
    'opening a SECOND master after popping the first targets that second '
    'master — no keepAlive bleed',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, countHeader('2 послуги'));
      expect(recordedUris, contains(salonServicesUri(_kMasterRowId)));
      // fixed-wait-ok: draining the entry transition — see the delete case.
      await tester.pump(const Duration(seconds: 1));

      // Back to the roster, then into the OTHER master.
      router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMember2UserId));
      await pumpUntil(tester, find.byType(SalonStaffProfileScreen));
      // Drain the route transition before navigating again: a second `go`
      // issued mid-transition reparents the shell Navigator's pages and
      // flutter_test fails the frame with "Duplicate GlobalKey".
      // fixed-wait-ok: draining an in-flight transition, not polling a widget
      // condition.
      await tester.pump(const Duration(seconds: 1));
      router.go(
        RouteNames.salonManageStaffServices(_kSalonId, _kMember2UserId),
      );
      // Pump on the RECORDED CALL, not on the rendered count: the count
      // header reads «2 послуги» for BOTH masters in this fixture, so a
      // finder-based wait would return on master 1's stale frame and make the
      // assertion below race (`project_fixture_values_can_defang_assertions`).
      await pumpWhile(
        tester,
        () => recordedUris.contains(salonServicesUri(_kMaster2RowId)),
      );

      final int m2Calls = recordedUris
          .where((u) => u == salonServicesUri(_kMaster2RowId))
          .length;
      expect(
        m2Calls,
        greaterThanOrEqualTo(1),
        reason:
            'the second master must be FETCHED, not served from the first '
            "master's keepAlive cache. Asserting only that no M1 request "
            'appeared would pass on an all-failing fixture.',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 5. `/masters//` NEVER REACHES THE WIRE (D4).
  // -------------------------------------------------------------------------

  testWidgets(
    'while the roster is loading no request with an EMPTY master segment is '
    'emitted, and a real request follows once it resolves',
    (tester) async {
      final gate = Completer<void>();
      _ControlledRoster.gate = gate;

      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(
        tester,
        find.byKey(const Key('salon_master_services_loading')),
      );
      expect(
        find.byKey(const Key('salon_master_services_loading')),
        findsOneWidget,
        reason:
            'D4 — an unresolved master id is a LOADING state, never an '
            'empty-string call',
      );
      expect(find.byType(ServicesListScreen), findsNothing);

      gate.complete();
      await pumpUntil(tester, countHeader('2 послуги'));

      expect(
        recordedUris.where((u) => u.contains('//services')),
        isEmpty,
        reason: '/salons/S/masters//services must never reach the wire',
      );
      expect(
        recordedUris,
        isNotEmpty,
        reason:
            'anti-vacuity — without this an all-failing fixture that emits '
            'nothing at all satisfies the assertion above',
      );
    },
  );

  // -------------------------------------------------------------------------
  // AUDIT F3 — a RELOAD of the roster must not tear the scope down.
  // -------------------------------------------------------------------------

  testWidgets(
    'a RELOAD of the roster keeps the ProviderScope and the nested Navigator '
    'alive — the scoped chain is not rebuilt and no skeleton flashes',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, countHeader('2 послуги'));

      final ProviderContainer scopedBefore = ProviderScope.containerOf(
        tester.element(find.byType(ServicesListScreen)),
        listen: false,
      );

      // Hold the RELOAD in flight, then trigger it. It must be a genuine
      // RELOAD — the roster rebuilding because a DEPENDENCY changed (its
      // `authProvider` identity watch) — not the REFRESH an `invalidate`
      // produces: `when`'s `skipLoadingOnRefresh` defaults to TRUE, so an
      // invalidate is already seamless and would leave this case green under
      // the broken shape too. `skipLoadingOnReload` is the one that defaults
      // to FALSE, which is exactly what made `view` swap the ProviderScope for
      // a Scaffold here. (Measured: with `invalidate` this test stayed GREEN
      // under the reverted fix — a vacuous pin.)
      _ControlledRoster.gate = Completer<void>();
      (container.read(authProvider.notifier) as _MutableAuthNotifier).signInAs(
        _kOtherAdmin,
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('salon_master_services_loading')),
        findsNothing,
        reason:
            'the shell gates on the RETAINED roster value, so a reload must '
            'not swap the subtree for a skeleton',
      );
      expect(
        find.byType(ServicesListScreen),
        findsOneWidget,
        reason:
            'the nested Navigator (and any in-flight ServiceSetupScreen '
            'multi-select on it) must survive the reload',
      );
      expect(
        identical(
          ProviderScope.containerOf(
            tester.element(find.byType(ServicesListScreen)),
            listen: false,
          ),
          scopedBefore,
        ),
        isTrue,
        reason:
            'the SAME child container — a rebuilt ProviderScope disposes the '
            'old one and every keepAlive provider in it',
      );
      expect(
        scopedBefore.read(serviceTargetProvider),
        isA<SalonMasterTarget>().having(
          (SalonMasterTarget t) => t.masterId,
          'masterId',
          _kMasterRowId,
        ),
        reason:
            'anti-vacuity — reading a DISPOSED ProviderContainer throws, so '
            'this proves the child container is still alive and still carries '
            'the override, not merely that some container was returned',
      );

      _ControlledRoster.gate!.complete();
      await tester.pump();
    },
  );

  // -------------------------------------------------------------------------
  // AUDIT cycle 2, item A — a POST-LOAD failure is SURFACED, not swallowed.
  // -------------------------------------------------------------------------

  testWidgets(
    'a roster reload that FAILS after a successful load surfaces an error '
    'snack and KEEPS the scope — the failure is neither swallowed nor '
    'allowed to tear the subtree down',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, countHeader('2 послуги'));

      final ProviderContainer scopedBefore = ProviderScope.containerOf(
        tester.element(find.byType(ServicesListScreen)),
        listen: false,
      );
      expect(
        find.byType(VelvetSnack),
        findsNothing,
        reason:
            'precondition — a successful load must NOT snack, otherwise the '
            'assertion below passes on noise the happy path already emits',
      );

      // A genuine RELOAD (the identity dependency changed) whose rebuild
      // THROWS. `invalidate` would produce a REFRESH, which retains the value
      // the same way and would leave this case green either way.
      _ControlledRoster.failNext = true;
      (container.read(authProvider.notifier) as _MutableAuthNotifier).signInAs(
        _kOtherAdmin,
      );
      await pumpUntil(tester, find.byType(VelvetSnack));
      await pumpVelvetSnackIn(tester);

      // Scoped to the snack ON PURPOSE, unlike `expectVelvetSnack`'s unscoped
      // finder: the salon role-home `/salons/S/shell` page is still on the
      // stack underneath and watches the SAME roster family, so it renders
      // its own `ErrorState` carrying the identical copy. An unscoped
      // `find.text` therefore matches twice and says nothing about WHICH
      // widget carries it — the whole point of this case.
      final Finder snack = find.byType(VelvetSnack);
      expect(snack, findsOneWidget);
      // Copy pulled from AppLocalizations, never a Cyrillic literal — the
      // string must be the one `UnauthorizedFailure.userMessage` resolves, and
      // a hard-coded literal breaks the day EN ships
      // (`scripts/forbid_cyrillic_finder.sh`).
      final String expectedCopy = AppLocalizations.of(
        tester.element(find.byType(ServicesListScreen)),
      ).errUnauthorized;
      expect(
        find.descendant(of: snack, matching: find.text(expectedCopy)),
        findsOneWidget,
        reason:
            "the copy comes off the Failure itself (`userMessage`) — no new "
            'ARB key, which phase 317 forbids',
      );
      expect(
        tester.widget<VelvetSnack>(snack).variant,
        VelvetSnackVariant.error,
      );

      // NON-DESTRUCTIVE: the same scope, the same nested Navigator, the same
      // screen. An "unmount on error" remedy would fail all three.
      expect(
        find.byType(ServicesListScreen),
        findsOneWidget,
        reason:
            'the subtree must survive — tearing it down on a transient '
            'failure is exactly the mid-edit teardown F3 exists to prevent',
      );
      expect(
        find.byKey(const Key('salon_master_services_error')),
        findsNothing,
        reason: 'the retained-value branch still renders, not the error page',
      );
      expect(
        identical(
          ProviderScope.containerOf(
            tester.element(find.byType(ServicesListScreen)),
            listen: false,
          ),
          scopedBefore,
        ),
        isTrue,
      );
      expect(
        scopedBefore.read(serviceTargetProvider),
        isA<SalonMasterTarget>().having(
          (SalonMasterTarget t) => t.masterId,
          'masterId',
          _kMasterRowId,
        ),
        reason:
            'anti-vacuity — reading a DISPOSED container throws, so this '
            'proves the scope is genuinely still alive with its override',
      );

      await pumpPastVelvetSnack(tester);
    },
  );

  testWidgets(
    'D4 IS NOT WEAKENED by item A — an INITIAL failure with no retained value '
    'still renders the full-screen error state, and does NOT double up a snack',
    (tester) async {
      _ControlledRoster.failNext = true;

      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(
        tester,
        find.byKey(const Key('salon_master_services_error')),
      );

      expect(
        find.byKey(const Key('salon_master_services_error')),
        findsOneWidget,
      );
      expect(find.byType(ServicesListScreen), findsNothing);
      expect(
        recordedUris,
        isEmpty,
        reason: 'no roster, no master id, no repository call',
      );
      expect(
        find.byType(VelvetSnack),
        findsNothing,
        reason:
            "the listener's `hasValue` guard — with no retained value the "
            'full-screen error state already reports the failure, and a snack '
            'on top of it is duplicate noise',
      );
    },
  );

  // -------------------------------------------------------------------------
  // QA (2026-09-10) — the INITIAL-load error state is not a dead end.
  // -------------------------------------------------------------------------

  testWidgets(
    'the initial-load error state offers a RETRY that re-fetches the roster '
    'and recovers into the real subtree',
    (tester) async {
      _ControlledRoster.failNext = true;

      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(
        tester,
        find.byKey(const Key('salon_master_services_error')),
      );

      // The affordance exists at all. Until phase 318's tile lands the ONLY
      // way into this subtree is a deep link, so without a retry the operator
      // has no in-screen way back from a transient roster failure.
      final Finder retry = find.descendant(
        of: find.byKey(const Key('salon_master_services_error')),
        matching: find.byType(FilledButton),
      );
      expect(
        retry,
        findsOneWidget,
        reason:
            '56 of the 60 ErrorState call sites in lib/ carry an onRetry; a '
            'deep-link-only entry point is the last place to omit one',
      );

      // …and it WORKS. Asserted on the recovered subtree, not merely on the
      // tap landing: an `onRetry` wired to the wrong provider family would
      // still render a button and still swallow the tap.
      _ControlledRoster.failNext = false;
      await tester.tap(retry);
      await pumpUntil(tester, countHeader('2 послуги'));

      expect(find.byType(ServicesListScreen), findsOneWidget);
      expect(
        find.byKey(const Key('salon_master_services_error')),
        findsNothing,
      );
      expect(
        recordedUris,
        contains(salonServicesUri(_kMasterRowId)),
        reason:
            'anti-vacuity — recovery means the SCOPED chain built and fetched, '
            'not merely that the error page unmounted',
      );
    },
  );

  testWidgets(
    'an ADMIN roster entry (masterId == null) renders the error gate and '
    'makes NO repository call',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(
        RouteNames.salonManageStaffServices(_kSalonId, _kAdminMemberUserId),
      );
      await pumpUntil(
        tester,
        find.byKey(const Key('salon_master_services_no_master')),
      );

      expect(
        find.byKey(const Key('salon_master_services_no_master')),
        findsOneWidget,
      );
      expect(find.byType(ServicesListScreen), findsNothing);
      expect(
        recordedUris,
        isEmpty,
        reason:
            'an admin entry has no `masters` row and no services — asserted '
            'on the CALL COUNT, not on the rendered text',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 7. AUTH BOUNDARY SURVIVES SCOPING.
  // -------------------------------------------------------------------------

  testWidgets(
    'an identity change inside the salon scope rebuilds the scoped repository '
    'AND emits a fresh request',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntil(tester, countHeader('2 послуги'));

      final ProviderContainer scoped = ProviderScope.containerOf(
        tester.element(find.byType(ServicesListScreen)),
        listen: false,
      );
      final Object before = scoped.read(serviceRepositoryProvider);
      final int callsBefore = recordedUris
          .where((u) => u == salonServicesUri(_kMasterRowId))
          .length;

      // A genuine logout would bounce the router to /login and unmount the
      // subtree outright — a stronger guarantee, but one that proves nothing
      // about the SCOPED element. Flipping the signed-in identity while the
      // scope stays mounted is the case that can actually go stale.
      (container.read(authProvider.notifier) as _MutableAuthNotifier).signInAs(
        _kOtherAdmin,
      );
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        final int now = recordedUris
            .where((u) => u == salonServicesUri(_kMasterRowId))
            .length;
        if (now > callsBefore) break;
        // fixed-wait-ok: pump-until on the recorded-call count.
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        identical(scoped.read(serviceRepositoryProvider), before),
        isFalse,
        reason:
            'the scoped element is a genuine build of the provider body, '
            'which watches the ROOT authProvider — scoping must not defeat '
            'the auth-boundary rebuild',
      );
      expect(
        recordedUris.where((u) => u == salonServicesUri(_kMasterRowId)).length,
        greaterThan(callsBefore),
        reason:
            'a rebuilt repository that never re-fetches leaves the previous '
            "account's catalogue on screen",
      );
    },
  );
}
