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
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
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
import '../helpers/route_pump.dart';
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

/// AUDIT cycle-2 (N3) — a SALON_OWNER. `User.salonId` is deliberately left
/// null: the owner arm of both `salonManageGuard` and `canManageSalon` binds
/// against `mySalonsProvider`, never against this field, so a non-null value
/// here could only mask which of the two is actually under test.
const User _kOwnerOfOtherSalon = User(
  id: 'owner-9',
  email: 'owner9@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Чужий',
  lastName: 'Власник',
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

/// AUDIT cycle-2 (N3) — a controllable [MySalons] so the SALON_OWNER arm of
/// `salonManageGuard` / `canManageSalonProvider` can be driven in both
/// directions.
///
/// `owned == null` reproduces the COLD DEEP LINK window the guard documents at
/// `app_router.dart:339-372`: with the list UNRESOLVED, `salonManageGuard`
/// deliberately ADMITS (it is synchronous and must never await), so the
/// request reaches the route BUILDER. That window is the whole reason
/// `_SalonManageServiceSetupRoute`'s widget-level gate exists, and it is the
/// only state in which that gate is observable — a RESOLVED list that excludes
/// the salon is bounced by the redirect one layer earlier (pinned by the third
/// row below).
class _ControlledMySalons extends MySalons {
  /// `null` → never completes (unresolved). Otherwise the owner's salons.
  static List<Salon>? owned;

  @override
  Future<List<Salon>> build() {
    final List<Salon>? o = owned;
    if (o == null) return Completer<List<Salon>>().future;
    return Future<List<Salon>>.value(o);
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
    _ControlledMySalons.owned = null;
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
        // AUDIT cycle-2 (N3). Inert for every pre-existing row in this file:
        // they all run as SALON_ADMIN, whose arm of `salonManageGuard` and
        // `canManageSalon` reads `User.salonId` and never touches this
        // provider.
        mySalonsProvider.overrideWith(_ControlledMySalons.new),
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

  /// Pumps until [key] names an ENABLED [IconButton] that is actually
  /// hit-testable. Both halves matter: the delete control is disabled while
  /// `serviceByIdProvider` resolves, and the page-transition slide leaves it
  /// off-screen for the first frames. Fixing the finder is the required
  /// remedy — never `warnIfMissed: false`
  /// (`project_animatedscale_root_breaks_tap_by_key`).
  Future<void> pumpUntilTappableIconButton(WidgetTester tester, Key key) async {
    final Finder finder = find.byKey(key);
    await pumpUntil(tester, () {
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
  ///
  /// 2026-09-13 audit (M13) — KEYED, not a raw-Cyrillic `find.text`. This
  /// used to be `countHeader(String text) => find.text(text)`, used as BOTH
  /// the pump-until condition AND the assertion: a copy change to the
  /// localized plural would have silently turned every wait into a timeout
  /// and every assertion into "not found yet", with no signal about which.
  /// `salon_master_own_services_route_test.dart:346` already fixed the
  /// identical pattern with this exact key; this brings the sibling in line.
  /// [countHeaderText] reads the rendered copy back out for the assertions
  /// that genuinely verify it.
  Finder countHeader() => find.byKey(const Key('services_count_header'));

  String countHeaderText(WidgetTester tester) {
    final Iterable<Element> found = countHeader().evaluate();
    if (found.isEmpty) return '';
    return (found.single.widget as Text).data ?? '';
  }

  /// Pumps until the count header reads exactly [expected]. Separate from
  /// [pumpUntilFound] because the interesting waits here are "until the count
  /// CHANGES", not "until the header exists".
  Future<void> pumpUntilCount(WidgetTester tester, String expected) =>
      pumpUntil(tester, () => countHeaderText(tester) == expected);

  // -------------------------------------------------------------------------
  // 8. PAGE TYPE — never a location string.
  // -------------------------------------------------------------------------

  group('page TYPE resolution (never the location string)', () {
    testWidgets('…/services builds ServicesListScreen', (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntilFound(tester, find.byType(ServicesListScreen));

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
        await pumpUntilFound(tester, find.byType(ServiceSetupScreen));

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
      await pumpUntilFound(tester, find.byType(ServiceEditScreen));

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
        await pumpUntilFound(tester, find.byType(ServicesListScreen));

        final ServicesListScreen screen = tester.widget<ServicesListScreen>(
          find.byType(ServicesListScreen),
        );

        // 2026-09-13 audit (M17) — this used to assert
        // `screen.setupRoute, isNull` / `screen.editRouteBuilder, isNull`:
        // pure widget-field reads that prove nothing about what the screen
        // does with them (`project_widget_field_assertion_is_vacuous`).
        // Replaced by the RENDERED consequence.
        //
        // Why the observation DISCRIMINATES: the salon setup leaf is
        // `/salons/:salonId/manage/staff/:memberId/services/setup`, guarded by
        // `salonManageGuard`, which BOUNCES an INDEPENDENT_MASTER away — so
        // had the root route leaked a salon `setupRoute`, no
        // `ServiceSetupScreen` would mount at all. Mounting one is only
        // possible via the root `/services/setup` literal.
        // Either "add services" CTA reaches the SAME destination
        // (`resolvedSetupRoute`): the FAB when the catalogue is non-empty, the
        // empty-state button when it is not. Which one this fixture renders
        // depends on the generated-client stub, not on anything this test is
        // about, so it takes whichever is on screen.
        final Finder createCta = find.byWidgetPredicate(
          (Widget w) =>
              w.key == const Key('btn-create-service') ||
              w.key == const Key('btn-create-service-empty'),
        );
        await pumpUntilFound(tester, createCta);
        await tester.tap(createCta.first);
        await tester.pump();
        await pumpUntilFound(tester, find.byType(ServiceSetupScreen));
        expect(
          find.byType(ServiceSetupScreen),
          findsOneWidget,
          reason:
              "D3's defaults must be untouched on the root route — the FAB "
              'must reach the ROOT /services/setup screen, which the '
              'salonManageGuard-protected salon leaf could never render for '
              'an INDEPENDENT_MASTER',
        );
        expect(
          find.byKey(const Key('salon_manage_service_setup_error')),
          findsNothing,
          reason:
              'and it must be the root screen, not the salon leaf rendering '
              'its unauthorized state',
        );

        // The resolution RULES themselves — pure functions over the two
        // nullable params, asserted on their output rather than on the
        // params' storage.
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
      await pumpUntilCount(tester, '2 послуги');

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
    await pumpUntilCount(tester, '2 послуги');

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
      await pumpUntilFound(tester, find.byType(ServicesListScreen));
      await pumpUntil(tester, () => _StubMasterProfile.builds > 0);

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
      await pumpUntilCount(tester, '2 послуги');

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
      await pumpUntilCount(tester, '2 послуги');
      expect(countHeaderText(tester), '2 послуги');
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
      await pumpUntilFound(
        tester,
        find.byKey(const Key('delete-service-dialog')),
      );
      await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byType(ServicesListScreen).hitTestable(),
      );
      // Give the post-delete invalidation + re-fetch a chance to land.
      await pumpUntilCount(tester, '1 послуга');

      expect(
        recordedUris,
        contains('DELETE ${salonServicesUri(_kMasterRowId)}/def-1'),
        reason:
            'phase 316 — with a salon target the delete must UNASSIGN, never '
            'DELETE /services/{id}, which would destroy a shared definition',
      );
      expect(
        countHeaderText(tester),
        '1 послуга',
        reason:
            'D2 — the invalidation fired from the EDIT leaf must reach the '
            "LIST leaf's keepAlive provider, so the list RE-RENDERS with the "
            'deleted row gone. With three per-route scopes it lands in a '
            'different chain and the list still reads «2 послуги».',
      );
      expect(
        countHeaderText(tester),
        isNot('2 послуги'),
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
      await pumpUntilCount(tester, '2 послуги');
      expect(recordedUris, contains(salonServicesUri(_kMasterRowId)));
      // fixed-wait-ok: draining the entry transition — see the delete case.
      await tester.pump(const Duration(seconds: 1));

      // Back to the roster, then into the OTHER master.
      router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMember2UserId));
      await pumpUntilFound(tester, find.byType(SalonStaffProfileScreen));
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
      await pumpUntil(
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
      await pumpUntilFound(
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
      await pumpUntilCount(tester, '2 послуги');

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
      await pumpUntilCount(tester, '2 послуги');

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
      await pumpUntilCount(tester, '2 послуги');

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
      await pumpUntilFound(tester, find.byType(VelvetSnack));
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
      await pumpUntilFound(
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
      await pumpUntilFound(
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
      await pumpUntilCount(tester, '2 послуги');

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
      await pumpUntilFound(
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
      await pumpUntilCount(tester, '2 послуги');

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

  // ---------------------------------------------------------------------
  // mobile-security audit (phase 318, cycle 1) — LOW, pre-existing.
  //
  // `salonManageStaffServices`/`salonManageStaffServiceSetup` compose ON TOP
  // of `salonManageStaffMember` (which encodes `memberId`) and
  // `salonPublicProfile` (which encodes `salonId`) rather than encoding
  // those two ids themselves — that is CORRECT, not an omission: encoding
  // them again here would DOUBLE-ENCODE (`%20` -> `%2520`) and break every
  // route in this subtree. `salonManageStaffServiceEdit` is different: it
  // adds its OWN new segment (`serviceId`) that no base builder already
  // covers, so it calls `Uri.encodeComponent` on that one segment directly.
  //
  // These pure, router-free cases feed a hostile id through all three
  // builders and pin that inherited/direct split — a future sibling copied
  // from any of them without reading the doc comments would regress it
  // silently (no analyzer or lint catches a double-encode).
  // ---------------------------------------------------------------------

  group('RouteNames salon-master-services builders — hostile-id encoding '
      '(mobile-security LOW, phase 318 cycle 1)', () {
    // 'a%2Fb' is deliberately NOT in this list — a raw '%' in the INPUT
    // legitimately becomes '%25' on a single, correct encode (turning the
    // literal string "a%2Fb" into "a%252Fb" is NOT a double-encode bug);
    // the dedicated "%" case below tests that distinction properly by
    // checking against %2525, not %252F.
    const List<String> hostileIds = <String>['a b', 'a/b'];

    for (final String hostile in hostileIds) {
      test('salonManageStaffServices("$hostile", "$hostile") is encoded '
          'EXACTLY ONCE and round-trips to the literal id', () {
        final String path = RouteNames.salonManageStaffServices(
          hostile,
          hostile,
        );
        expect(
          Uri.parse(path).pathSegments,
          <String>['salons', hostile, 'manage', 'staff', hostile, 'services'],
          reason: 'the encoded id must DECODE back to the exact input',
        );
        expect(
          path,
          allOf(isNot(contains('%2520')), isNot(contains('%252F'))),
          reason:
              'doubled escapes (%20 -> %2520, %2F -> %252F) are the '
              'double-encode regression this pin guards against',
        );
      });

      test('salonManageStaffServiceSetup("$hostile", "$hostile") is encoded '
          'EXACTLY ONCE and round-trips to the literal id', () {
        final String path = RouteNames.salonManageStaffServiceSetup(
          hostile,
          hostile,
        );
        expect(Uri.parse(path).pathSegments, <String>[
          'salons',
          hostile,
          'manage',
          'staff',
          hostile,
          'services',
          'setup',
        ]);
        expect(path, allOf(isNot(contains('%2520')), isNot(contains('%252F'))));
      });

      test(
        'salonManageStaffServiceEdit("$hostile", "$hostile", "$hostile") '
        'is encoded EXACTLY ONCE on every segment, INHERITED and OWN alike',
        () {
          final String path = RouteNames.salonManageStaffServiceEdit(
            hostile,
            hostile,
            hostile,
          );
          expect(Uri.parse(path).pathSegments, <String>[
            'salons',
            hostile,
            'manage',
            'staff',
            hostile,
            'services',
            hostile,
            'edit',
          ]);
          expect(
            path,
            allOf(isNot(contains('%2520')), isNot(contains('%252F'))),
          );
        },
      );
    }

    // A bare '%' round-trips through Uri.encodeComponent to '%25' — this
    // one is the case that actually DISTINGUISHES "encoded once" from
    // "encoded twice": a double-encode would turn the ALREADY-ONE-STEP
    // '%25' into '%2525', which is exactly what a stray second
    // `Uri.encodeComponent` call on an already-encoded upstream segment
    // would produce.
    test('a literal "%" id is encoded to a single %25, never %2525', () {
      final String services = RouteNames.salonManageStaffServices('%', '%');
      expect(Uri.parse(services).pathSegments, <String>[
        'salons',
        '%',
        'manage',
        'staff',
        '%',
        'services',
      ]);
      expect(services, isNot(contains('%2525')));

      final String edit = RouteNames.salonManageStaffServiceEdit('%', '%', '%');
      expect(Uri.parse(edit).pathSegments, <String>[
        'salons',
        '%',
        'manage',
        'staff',
        '%',
        'services',
        '%',
        'edit',
      ]);
      expect(edit, isNot(contains('%2525')));
    });

    // '..' is the one hostile id `Uri.encodeComponent` does NOT escape at
    // all — a dot is an unreserved RFC 3986 character, so
    // `Uri.encodeComponent('..') == '..'` verbatim. That is correct,
    // spec-conformant Dart behaviour, not a double-encoding bug in these
    // builders (there is nothing to double-encode). What matters for
    // "cannot escape the intended path" is the FAIL-CLOSED direction: a
    // literal '..' segment does not resolve into some OTHER *valid*
    // `/salons/:salonId/...` route with an attacker-chosen salonId — when
    // parsed, it collapses the preceding 'salons' segment instead, which
    // no longer matches this subtree's registered route pattern at all —
    // go_router 17.2.3 applies the same `Uri.parse` normalization on the
    // real navigation path before matching (`configuration.dart:648`,
    // `findMatch(normalizeUri(Uri.parse(...)))`), and no bare
    // `/manage/staff/:memberId/services` route is registered, so the
    // collapsed path matches nothing and fails closed (404), not a
    // guard-redirect (`salon_manage_route_guard_test.dart` covers
    // `salonManageGuard`'s role/ownership redirects for matched routes
    // only, not unmatched-location 404 behaviour).
    test('a literal ".." salonId is NOT re-escaped by Uri.encodeComponent, '
        'and the raw string cannot masquerade as a different valid '
        '/salons/:salonId prefix once parsed', () {
      expect(Uri.encodeComponent('..'), '..');

      final String path = RouteNames.salonManageStaffServices('..', 'member-1');
      expect(path, '/salons/../manage/staff/member-1/services');

      // Parsing (what a `Uri`-based router does with the location)
      // collapses 'salons/..' away entirely rather than resolving to a
      // DIFFERENT concrete salonId segment — there is no salonId capture
      // left to escape with.
      expect(
        Uri.parse(path).pathSegments,
        isNot(contains('salons')),
        reason:
            'the traversal collapses the very segment a route match '
            'needs, so this cannot land on a valid — merely wrong — '
            'salon; it fails to match at all',
      );
    });
  });

  // -------------------------------------------------------------------------
  // AUDIT cycle-2 (N3) — the /services/setup leaf's OWN authorization gate.
  //
  // `_SalonManageServiceSetupRoute` (`app_router.dart:2489`) gates
  // `/salons/:salonId/manage/staff/:memberId/services/setup` on
  // `canManageSalonProvider(salonId)` and renders the shared [ErrorState]
  // keyed `salon_manage_service_setup_error` when it is false. Nothing pinned
  // that: pointing the builder back at a bare [ServiceSetupScreen] left the
  // whole suite green.
  //
  // WHY THE DENY ARM USES AN UNRESOLVED `mySalonsProvider`, not a resolved
  // list that excludes the salon: `salonManageGuard` is synchronous, so for a
  // SALON_OWNER it can only bind against an ALREADY-RESOLVED list and
  // deliberately ADMITS while the list is unresolved (`app_router.dart:
  // 339-372`). That admit window — a cold deep link from an owner whose
  // ownership of THIS salon has not been established — is the only state in
  // which the builder runs for an unauthorized viewer, and it is exactly what
  // the widget-level gate is defence-in-depth for. The third row pins the
  // outer layer for the resolved-and-excluded case, so both halves of the
  // brief's "owner of a different salon" are covered, each at its own layer.
  // -------------------------------------------------------------------------

  group('the /services/setup leaf gates on canManageSalon', () {
    testWidgets(
      'DENY: a cold deep link whose ownership is unresolved renders the '
      'unauthorized state, NOT ServiceSetupScreen',
      (tester) async {
        _MutableAuthNotifier.seed = _kOwnerOfOtherSalon;
        _ControlledMySalons.owned = null; // cold — never resolves

        final container = makeContainer();
        final router = await pumpRouter(tester, container);

        router.go(
          RouteNames.salonManageStaffServiceSetup(_kSalonId, _kMemberUserId),
        );
        await pumpUntilFound(
          tester,
          find.byKey(const Key('salon_manage_service_setup_error')),
        );

        expect(
          find.byKey(const Key('salon_manage_service_setup_error')),
          findsOneWidget,
        );
        expect(
          find.byType(ServiceSetupScreen),
          findsNothing,
          reason:
              'the bulk-create FORM must never mount for a viewer whose '
              'management of this salon is not established — the screen takes '
              'no read-only flag, so gating the whole screen is the only '
              'gate there is',
        );
      },
    );

    testWidgets(
      'POSITIVE CONTROL: the genuine owner of this salon reaches the form',
      (tester) async {
        _MutableAuthNotifier.seed = _kOwnerOfOtherSalon;
        _ControlledMySalons.owned = const <Salon>[
          Salon(id: _kSalonId, name: 'Салон'),
        ];

        final container = makeContainer();
        final router = await pumpRouter(tester, container);

        router.go(
          RouteNames.salonManageStaffServiceSetup(_kSalonId, _kMemberUserId),
        );
        await pumpUntilFound(tester, find.byType(ServiceSetupScreen));

        expect(
          find.byType(ServiceSetupScreen),
          findsOneWidget,
          reason:
              'without this arm the DENY row above would pass just as well '
              'against a gate that refuses EVERYONE',
        );
        expect(
          find.byKey(const Key('salon_manage_service_setup_error')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the OUTER layer: once the owner list RESOLVES and excludes this salon, '
      'salonManageGuard bounces before the leaf ever builds',
      (tester) async {
        _MutableAuthNotifier.seed = _kOwnerOfOtherSalon;
        _ControlledMySalons.owned = const <Salon>[
          Salon(id: 'salon-OTHER', name: 'Інший салон'),
        ];

        final container = makeContainer();
        final router = await pumpRouter(tester, container);
        // Resolve the list BEFORE navigating: the guard reads it synchronously.
        await container.read(mySalonsProvider.future);
        // AUDIT cycle-3 (C5) — and SETTLE before navigating, not a single
        // `pump`. `roleHomePath(SALON_OWNER)` is `/salons/home`, whose
        // `SalonHomeResolverScreen` forwards to the one salon this owner
        // actually holds from a POST-FRAME callback. Resolving the list arms
        // that forward; issuing the `go` one frame later means the forward
        // fires AFTERWARDS and clobbers it, so the row ends up observing the
        // RESOLVER rather than the guard. Measured: with `salonManageGuard`'s
        // owner-exclusion branch (`app_router.dart:374-377`) deleted outright,
        // every assertion below still passed. Settling first makes the `go`
        // start from a quiet router, so the guard is the only thing that can
        // move it.
        await tester.pumpAndSettle();

        router.go(
          RouteNames.salonManageStaffServiceSetup(_kSalonId, _kMemberUserId),
        );
        // AUDIT cycle-3 (C5) — this row used to read
        //   await pumpWhile(tester, () => find.byType(ServiceSetupScreen)
        //       .evaluate().isEmpty);
        // and then assert only `findsNothing` on that same screen.
        //
        // That helper RETURNS THE INSTANT ITS CONDITION HOLDS — it was a
        // pump-UNTIL wearing a pump-WHILE name. Handed "the setup screen is
        // absent", the condition is already true on entry, so the loop pumped
        // ZERO frames and the sole assertion ran against the tree as it stood
        // BEFORE the `router.go(...)` had rendered anything. It could not
        // have failed. (The misnaming itself was fixed in the 2026-09-13
        // audit: the helper is now `pumpUntil` in
        // `test/helpers/route_pump.dart`, shared by all three suites.)
        //
        // `pumpAndSettle` instead, so the redirect is actually resolved and
        // painted before anything is asserted.
        await tester.pumpAndSettle();

        expect(find.byType(ServiceSetupScreen), findsNothing);

        // The row's own claim is "bounces BEFORE THE LEAF EVER BUILDS", and
        // that is what distinguishes it from its two siblings: the DENY row
        // above lets the leaf build and pins its widget-level refusal, this
        // one must show the leaf never ran at all. Absence of the leaf's
        // unauthorized state is what says so — `findsNothing` on
        // `ServiceSetupScreen` alone is satisfied by BOTH layers.
        expect(
          find.byKey(const Key('salon_manage_service_setup_error')),
          findsNothing,
          reason:
              'the OUTER guard must bounce first — reaching the leaf and '
              'rendering its widget-level refusal means the route-level check '
              'stopped firing and only defence-in-depth is left',
        );

        // And WHERE the bounce landed, by PAGE TYPE — item 8 of this file's
        // own header, and the half the row was missing. No
        // `currentConfiguration.uri` read (`forbid_naive_router_location.sh`
        // enforces that repo-wide, and this file's header forbids location
        // strings outright).
        //
        // `roleHomePath(SALON_OWNER)` is `RouteNames.salonHome`, whose
        // `SalonHomeResolverScreen` forwards to the one salon this owner
        // actually holds — so the settled destination is that salon's
        // `SalonShellScreen`. Matched by PREDICATE on `salonId`, not by bare
        // type: `_kSalonId` and `'salon-OTHER'` both mount the same class, so
        // a bare `findsOneWidget` would stay green on a bounce that parked
        // the excluded owner inside the very salon the guard just refused —
        // the exact inversion this row exists to catch. Mirrors
        // `salon_manage_route_guard_test.dart`'s own shell predicate.
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == 'salon-OTHER',
          ),
          findsOneWidget,
          reason:
              'the bounce must RESOLVE to the salon this owner DOES hold, not '
              'merely change the URL and not park them in salon $_kSalonId',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Phase 323 — THE BACK AFFORDANCE.
  //
  // This leaf is a `ShellRoute` child declared WITHOUT a `navigatorKey`
  // (`app_router.dart:1270`), so go_router mints a PRIVATE nested `Navigator`
  // and the services list is page #1 inside it.
  // `ModalRoute.impliesAppBarDismissal` walks that navigator's own history,
  // reaches itself and returns false, so `AppBar.automaticallyImplyLeading`
  // draws nothing — the operator had NO on-screen way out. The fix is the
  // additive `ServicesListScreen.showBack`, opted into by exactly this route.
  //
  // WHY THIS COULD NOT PASS VACUOUSLY, and why the bug shipped anyway: BOTH
  // integration flows over this subtree exit PROGRAMMATICALLY
  // (`salon_owner_set_master_services_flow_test.dart` called `router.pop()`,
  // `salon_admin_…` uses `router.go(...)`). Those drive the router-level pop,
  // which genuinely worked, so they stayed green with no control on screen at
  // all. This case therefore asserts on the RENDERED CONTROL and TAPS IT —
  // never on `screen.showBack`, a field read that proves nothing about what
  // the AppBar does with it (`project_widget_field_assertion_is_vacuous`).
  // -------------------------------------------------------------------------

  testWidgets(
    'the owner/admin leaf RENDERS a back control, and TAPPING it returns to '
    'the staff profile',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      // Enter the way production does: the roster's staff profile PUSHES the
      // catalogue. `go` would replace the stack and leave nothing to pop back
      // to, making the tap's destination an artefact of the test setup.
      router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMemberUserId));
      await pumpUntilFound(tester, find.byType(SalonStaffProfileScreen));
      // fixed-wait-ok: draining the entry transition before pushing again —
      // the "Duplicate GlobalKey" hazard this file documents at :946.
      await tester.pump(const Duration(seconds: 1));

      unawaited(
        router.push<void>(
          RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId),
        ),
      );
      await pumpUntilCount(tester, '2 послуги');

      final Finder back = find.byKey(ServicesListScreen.backKey);
      expect(
        back,
        findsOneWidget,
        reason:
            'the shell-nested leaf suppresses the automatic arrow, so the '
            'explicit control is the ONLY on-screen exit this role has',
      );

      // hitTestable(), not a bare finder: the entry transition leaves the
      // AppBar off-screen for the first frames, and papering that over with
      // `warnIfMissed: false` is the banned remedy
      // (`project_animatedscale_root_breaks_tap_by_key`).
      await pumpUntil(tester, () => back.hitTestable().evaluate().isNotEmpty);
      await tester.tap(back);
      // Wait on the LEAF DISAPPEARING, not on the profile appearing: the
      // profile sits below the pushed leaf and is already in the tree, so
      // `pumpUntilFound(SalonStaffProfileScreen)` returns on frame 0 and the
      // assertions below would race the pop transition.
      await pumpUntil(
        tester,
        () => find.byType(ServicesListScreen).evaluate().isEmpty,
      );

      expect(
        find.byType(SalonStaffProfileScreen),
        findsOneWidget,
        reason: 'the tap must POP, not merely animate something',
      );
      expect(
        find.byType(ServicesListScreen),
        findsNothing,
        reason:
            'anti-vacuity — the staff profile sits BELOW the pushed leaf in '
            'the stack, so "the profile is on screen" is already true before '
            'the tap. Only the leaf being GONE proves the pop happened.',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 10. THE BACK ARROW ON AN EMPTY STACK — 2026-09-14 audit, security LOW.
  //
  // `GoRouterDelegate.pop` does NOT assert — it THROWS
  // `GoError('There is nothing to pop')` in release as well
  // (`go_router-17.2.3/lib/src/delegate.dart:100-105`). The empty-stack state
  // is reachable on THIS route and no other: `service_setup_screen.dart`'s
  // own no-stack branch calls `context.go(exitRoute)`, and `app_router.dart`'s
  // `_SalonManageServiceSetupRoute` aims that `exitRoute` at
  // `RouteNames.salonManageStaffServices(...)` — this very leaf. Because the
  // same mount passes `showBottomNav: false`, the arrow is the operator's ONLY
  // on-screen exit, so an unguarded `context.pop()` throws and strands them
  // inside the privileged salon-manage shell.
  //
  // WHY THIS CANNOT PASS VACUOUSLY:
  //   • it asserts `router.canPop() == false` BEFORE the tap, so a setup that
  //     accidentally left something poppable fails loudly instead of silently
  //     degrading into a re-run of the case above;
  //   • it asserts `tester.takeException()` is null — a `GoError` raised
  //     inside a gesture callback is swallowed into the pending-exception
  //     slot, so "the pump finished" alone proves nothing;
  //   • it asserts the leaf is GONE and the fallback page is on screen, so an
  //     absorbed no-op tap (the `backFallbackRoute: null` behaviour) fails
  //     too.
  // -------------------------------------------------------------------------

  testWidgets(
    'with an EMPTY root stack the back arrow does not throw and lands on the '
    'fallback staff profile',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      // `go`, not `push` — this is the `ServiceSetupScreen` no-stack branch's
      // own entry verb, and it replaces the stack so nothing is poppable.
      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntilCount(tester, '2 послуги');

      expect(
        router.canPop(),
        isFalse,
        reason:
            'anti-vacuity — the whole point of this case is the EMPTY stack. '
            'If anything is poppable here this is just a duplicate of the '
            'push-entry case above and proves nothing about the guard.',
      );

      final Finder back = find.byKey(ServicesListScreen.backKey);
      expect(back, findsOneWidget);
      await pumpUntil(tester, () => back.hitTestable().evaluate().isNotEmpty);
      await tester.tap(back);
      await pumpUntil(
        tester,
        () => find.byType(ServicesListScreen).evaluate().isEmpty,
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a bare `context.pop()` raises GoError("There is nothing to pop") '
            'here; the gesture arena swallows it into the pending-exception '
            'slot, so this assertion is what makes the crash visible',
      );
      expect(
        find.byType(SalonStaffProfileScreen),
        findsOneWidget,
        reason:
            'the guard must GO to `backFallbackRoute`, not merely absorb the '
            'tap — an absorbed tap leaves the operator exactly as stranded',
      );
      expect(find.byType(ServicesListScreen), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // 11. THE BACK ARROW'S ACCESSIBILITY CONTRACT — mobile-qa gap closure,
  // 2026-09-14.
  //
  // Phase 323 added a NEW ARB key (`servicesListBackSemanticLabel`, mirrored
  // in `app_uk.arb` + `app_en.arb`) and threaded it into
  // `NeumorphicIconButton.semanticLabel`. Nothing asserted it arrived.
  //
  // That matters more here than on a typical bar: this control is an
  // ICON-ONLY arrow and — because the shell-nested leaf suppresses the
  // automatic one — it is the operator's ONLY on-screen exit. Unlabelled, a
  // TalkBack user is told "button" and nothing else, on the one control that
  // gets them out of the privileged salon-manage shell.
  //
  // Asserted against the RENDERED SEMANTICS TREE (`tester.getSemantics`),
  // never against `NeumorphicIconButton.semanticLabel`
  // (`project_widget_field_assertion_is_vacuous` — a field read passes even
  // if the widget never emits a `Semantics` node), and against
  // `l10n.servicesListBackSemanticLabel` rather than the literal 'Назад'
  // (M2/M11 — a literal here re-breaks the moment EN renders).
  // -------------------------------------------------------------------------

  testWidgets(
    'the back arrow carries the servicesListBackSemanticLabel ARB copy and '
    'is announced as a tappable BUTTON',
    (tester) async {
      // Disposed INSIDE the body, not via addTearDown: the framework's
      // end-of-test verification runs BEFORE tearDowns and fails on a live
      // handle.
      final SemanticsHandle handle = tester.ensureSemantics();

      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
      await pumpUntilCount(tester, '2 послуги');

      final Finder back = find.byKey(ServicesListScreen.backKey);
      expect(back, findsOneWidget);

      final AppLocalizations l10n = AppLocalizations.of(tester.element(back));
      // Anti-vacuity: an ARB key that resolved to the empty string would make
      // every assertion below pass while announcing nothing.
      expect(
        l10n.servicesListBackSemanticLabel,
        isNotEmpty,
        reason: 'the new ARB key must actually carry copy in the uk locale',
      );

      expect(
        tester.getSemantics(back),
        isSemantics(
          label: l10n.servicesListBackSemanticLabel,
          isButton: true,
          hasTapAction: true,
        ),
        reason:
            'icon-only, and the ONLY on-screen exit from the salon-manage '
            'shell for this role — an unlabelled node announces just '
            '"button"',
      );

      // NO TOUCH-TARGET ASSERTION HERE, DELIBERATELY. Two drafts of one were
      // written and both were MUTATION-PROVED VACUOUS (2026-09-14): with
      // `NeumorphicIconButton.extent` cut 48 -> 40 they both stayed green.
      // `AppBar` hands its `leading` slot TIGHT 56 x 56 constraints, and
      // `NeumorphicIconButton`'s `Container(48, 48)` lowers to a
      // `ConstrainedBox(tightFor(48, 48))` whose `enforce()` clamps straight
      // back up — so the gesture box measures 56 x 56 no matter what the
      // button asks for, on the keyed `Semantics` node AND on the
      // `GestureDetector` inside it.
      //
      // The touch target is therefore a property of `AppBar`, not of this
      // change, and an assertion on it could only ever go red by editing
      // Flutter. Shipping one would be a rubber stamp (M16) — worse than the
      // gap, because the next reader would believe the target was guarded.
      //
      // (Two side notes this probe settled: the GEOMETRY NOTE in
      // `services_list_screen.dart` documents "56 x 48 ... 4 dp above and
      // below" — the measured box is 56 x 56, so the note is wrong about the
      // vertical clearance, though its conclusion that the light shadow is
      // clipped horizontally stands. And the target comfortably clears
      // `kMinInteractiveDimension` either way.)

      handle.dispose();
    },
  );
}
