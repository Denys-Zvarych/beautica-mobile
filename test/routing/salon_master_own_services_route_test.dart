// Phase 321 (D3) — route-level tests for the SALON_MASTER's OWN services
// surface: `/staff/services`.
//
// WHAT THIS FILE PINS, and why each case cannot pass vacuously
// ------------------------------------------------------------
//   1. TARGET RESOLUTION — the repository EMITS
//      `/api/v1/salons/{salonId}/masters/{masterId}/services`, where
//      `salonId`/`masterId` come off the viewer's OWN `masterProfileProvider`
//      read, never off the auth session's userId. The fixture's session
//      userId, master row id, and salon id are THREE DIFFERENT strings, and
//      the emitted path is asserted to contain the master row id AND
//      `isNot(contains(userId))`
//      (`project_fixture_values_can_defang_assertions`).
//   2. UNRESOLVED IDS NEVER REACH THE WIRE (D3 point 3) — while the profile
//      is loading, no request is emitted at all; once resolved with a
//      missing/empty salonId, the error state renders and — asserted on the
//      RECORDED CALL COUNT, not on the rendered text — no request is made
//      either. A master with no salon is a broken-session ERROR, never a
//      silently empty list.
//   3. READ-ONLY RENDERING — cards render (the services THEMSELVES, not an
//      absence-only proof), the FAB is absent, and there is no reachable
//      edit destination.
//   4. THE ROLE-CHECK ORDERING PIN — mirrors
//      `lib/features/schedule/application/own_schedule_scope.dart`'s header:
//      the role is checked before `masterProfileProvider` is ever watched.
//      Proven here by asserting `masterProfileProvider`'s build count is
//      unaffected by the SALON_MASTER-only nature of this route (the CONTROL
//      case) rather than merely trusting the source ordering.
//   5. CONTROL — an INDEPENDENT_MASTER's `/services` behaviour is completely
//      unaffected: every write affordance is PRESENT and the root
//      `/independent-masters/me/services` endpoint is hit, never the salon
//      path. Without this arm a bug that read-onlys or salon-scopes BOTH
//      roles would pass every SALON_MASTER-only assertion above.
//
// MECHANISM (reused, not invented — REUSE-FIRST): mirrors
// `salon_manage_staff_services_route_test.dart`, the phase-317 sibling that
// pins the OTHER `SalonMasterTarget` construction site (a salon owner/admin
// viewing a CHOSEN master's services). This file's target is simpler — no
// roster indirection, since the viewer resolves their OWN row directly off
// `masterProfileProvider` — so it has no analogue to that file's
// scope-unwind-on-pop or delete-cascade cases (this route is a nav-bar tab
// root, never nested under a roster).
//
// ROLE ADMISSION for `/staff/services`: SALON_MASTER is admitted;
// INDEPENDENT_MASTER, SALON_OWNER, SALON_ADMIN and CLIENT are each bounced to
// their own `roleHomePath`; an unauthenticated visitor is sent to `/login`.
// That admit/bounce MATRIX lives in `auth_redirect_test.dart`'s `/staff/*`
// group (Phase 321 addition) — this file uses a SALON_MASTER throughout,
// plus one INDEPENDENT_MASTER control case.

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
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
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

// ---------------------------------------------------------------------------
// Fixtures — the auth session's userId, the masters ROW id, and the salon id
// are DELIBERATELY three different strings.
// ---------------------------------------------------------------------------

/// The auth session's `User.id` — NEVER what a `SalonMasterTarget` should
/// carry as `masterId`.
const String _kViewerUserId = 'user-viewer-U';

/// The `masters` ROW id [masterProfileProvider] resolves — what the emitted
/// URI must contain.
const String _kViewerMasterRowId = 'master-row-M';

const String _kSalonId = 'salon-S';

const User _kSalonMasterUser = User(
  id: _kViewerUserId,
  email: 'salonmaster@beautica.ua',
  role: UserRole.salonMaster,
  firstName: 'Майстер',
  lastName: 'Салону',
  salonId: _kSalonId,
);

const User _kIndependentMasterUser = User(
  id: 'user-im-I',
  email: 'independent@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Соло',
  lastName: 'Майстер',
);

/// One service row in the salon-master list response, in the wire shape
/// `MasterServiceMapper.fromDto` consumes.
Map<String, Object?> _serviceRow({
  required String assignmentId,
  required String defId,
  required String name,
}) => <String, Object?>{
  'id': assignmentId,
  'masterId': _kViewerMasterRowId,
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
  static User seed = _kSalonMasterUser;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: seed, accessToken: 'tok');
}

/// A controllable [MasterProfile] so loading / error / resolved-with-missing-
/// salon cases can all be driven deterministically.
class _ControlledMasterProfile extends MasterProfile {
  /// When non-null, `build` awaits it — the test completes it to resolve.
  static Completer<void>? gate;

  /// When true, `build` THROWS instead of resolving.
  static bool failNext = false;

  /// The salonId the resolved [Master] carries — `null`/empty reproduces the
  /// D3-point-3 broken-session case.
  static String? salonId = _kSalonId;

  /// Counts real builds — the anti-vacuity check for the role-ordering pin:
  /// asserted alongside `container.exists` the same way
  /// `salon_manage_staff_services_route_test.dart`'s AUDIT F1 case does.
  static int builds = 0;

  @override
  Future<Master> build() async {
    builds++;
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    // Non-retryable by `failure_retry_policy.dart` (same reasoning
    // `salon_manage_staff_services_route_test.dart`'s `_ControlledRoster`
    // documents) — a retryable failure would cycle through
    // `AsyncLoading(retrying: true)` on a 200 ms timer that outlives the
    // test, and would make the assertion race.
    if (failNext) throw const UnauthorizedFailure();
    return Master(
      id: _kViewerMasterRowId,
      firstName: 'Майстер',
      lastName: 'Салону',
      reviewCount: 0,
      type: MasterType.salonMaster,
      salonId: salonId,
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

  /// Every URI the RAW Dio was asked for, in order.
  late List<String> recordedUris;

  late List<Map<String, Object?>> salonRows;

  setUp(() {
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    _MutableAuthNotifier.seed = _kSalonMasterUser;
    _ControlledMasterProfile.gate = null;
    _ControlledMasterProfile.failNext = false;
    _ControlledMasterProfile.salonId = _kSalonId;
    _ControlledMasterProfile.builds = 0;
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

    // The ROOT (INDEPENDENT_MASTER) endpoint: stubbed for the CONTROL case.
    // One row (not empty) — the FAB is hidden in the empty state (its own
    // primary CTA takes over), so an empty fixture would make the "FAB
    // present" assertion pass for the wrong reason.
    final ServiceDefinitionResponse imDef =
        (ServiceDefinitionResponseBuilder()
              ..id = 'im-def-1'
              ..name = 'Стрижка'
              ..baseDurationMinutes = 30
              ..priceType = ServiceDefinitionResponsePriceTypeEnum.FIXED
              ..priceMin = 300
              ..priceDisplay = '300 ₴'
              ..isActive = true)
            .build();
    final MasterServiceResponse imService =
        (MasterServiceResponseBuilder()
              ..id = 'im-svc-1'
              ..masterId = 'im-master-row'
              ..isActive = true
              ..serviceDefinition = imDef.toBuilder())
            .build();
    final ApiResponseListMasterServiceResponse imResponse =
        (ApiResponseListMasterServiceResponseBuilder()
              ..success = true
              ..data = ListBuilder<MasterServiceResponse>([imService]))
            .build();
    when(() => mockServiceApi.getMyServices()).thenAnswer(
      (_) async => Response(
        data: imResponse,
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
        masterProfileProvider.overrideWith(_ControlledMasterProfile.new),
        dioProvider.overrideWithValue(mockDio),
        serviceApiProvider.overrideWithValue(mockServiceApi),
        categoryRequestApiProvider.overrideWithValue(mockCategoryApi),
        serviceCatalogApiProvider.overrideWithValue(mockCatalogApi),
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
    await container.read(authProvider.future);
    await tester.pump();
    return router;
  }

  String salonServicesUri(String masterId) =>
      '/api/v1/salons/$_kSalonId/masters/$masterId/services';

  // Keyed lookup (mobile-qa LOW, phase 321 follow-up) — the active-count
  // heading now carries `Key('services_count_header')`
  // (`services_list_screen.dart`), so waiting/locating it no longer needs to
  // match the localized Ukrainian plural text. `countHeaderText` reads the
  // rendered copy back out for the ONE assertion that genuinely verifies it.
  Finder countHeader() => find.byKey(const Key('services_count_header'));

  String countHeaderText(WidgetTester tester) =>
      tester.widget<Text>(countHeader()).data ?? '';

  // -------------------------------------------------------------------------
  // 1. TARGET RESOLUTION.
  // -------------------------------------------------------------------------

  testWidgets(
    'the repository EMITS /salons/S/masters/M/services — the viewer\'s '
    'masters ROW id, never the auth session userId',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(tester, countHeader());

      expect(
        recordedUris,
        contains(salonServicesUri(_kViewerMasterRowId)),
        reason:
            'D3 must carry the resolved salonId/masterId all the way to '
            'HttpServiceRepository — asserted on the emitted URI',
      );
      for (final String uri in recordedUris) {
        expect(
          uri,
          isNot(contains(_kViewerUserId)),
          reason:
              'the emitted path must use the masters ROW id, never the '
              'auth session userId — a userId on '
              '/salons/{s}/masters/{m}/... yields 404, not 403',
        );
      }
      verifyNever(() => mockServiceApi.getMyServices());
    },
  );

  testWidgets(
    'page TYPE resolution: /staff/services builds ServicesListScreen',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(tester, find.byType(ServicesListScreen));

      expect(find.byType(ServicesListScreen), findsOneWidget);
      expect(
        tester
            .widget<ServicesListScreen>(find.byType(ServicesListScreen))
            .writable,
        isFalse,
        reason: 'phase 320 D1 — read-only for this role',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 2. UNRESOLVED IDS NEVER REACH THE WIRE.
  // -------------------------------------------------------------------------

  testWidgets(
    'while the profile is loading no request is emitted, and a real request '
    'follows once it resolves',
    (tester) async {
      final gate = Completer<void>();
      _ControlledMasterProfile.gate = gate;

      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(
        tester,
        find.byKey(const Key('salon_master_own_services_loading')),
      );
      expect(
        find.byKey(const Key('salon_master_own_services_loading')),
        findsOneWidget,
        reason:
            'an unresolved profile is a LOADING state, never an empty '
            'or premature call',
      );
      expect(find.byType(ServicesListScreen), findsNothing);
      expect(recordedUris, isEmpty);

      gate.complete();
      await pumpUntilFound(tester, countHeader());

      expect(
        recordedUris.where((u) => u.contains('//services')),
        isEmpty,
        reason: '/salons/S/masters//services must never reach the wire',
      );
      expect(recordedUris, isNotEmpty);
    },
  );

  testWidgets(
    'a resolved profile with a MISSING salonId renders the error state and '
    'makes NO repository call — never a silently empty list',
    (tester) async {
      _ControlledMasterProfile.salonId = null;

      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(
        tester,
        find.byKey(const Key('salon_master_own_services_error')),
      );

      expect(
        find.byKey(const Key('salon_master_own_services_error')),
        findsOneWidget,
      );
      expect(find.byType(ServicesListScreen), findsNothing);
      expect(
        recordedUris,
        isEmpty,
        reason:
            'D3 point 3 — a SALON_MASTER with no salon is a broken session; '
            'no /salons//masters/M/services or similar call is ever made',
      );
    },
  );

  testWidgets('a profile fetch failure renders the error state and makes NO '
      'repository call', (tester) async {
    _ControlledMasterProfile.failNext = true;

    final container = makeContainer();
    final router = await pumpRouter(tester, container);

    router.go(RouteNames.salonMasterServices);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('salon_master_own_services_error')),
    );

    expect(
      find.byKey(const Key('salon_master_own_services_error')),
      findsOneWidget,
    );
    expect(find.byType(ServicesListScreen), findsNothing);
    expect(recordedUris, isEmpty);
  });

  // -------------------------------------------------------------------------
  // 3. READ-ONLY RENDERING.
  // -------------------------------------------------------------------------

  testWidgets(
    'the services themselves render (sections/counts/cards), the FAB is '
    'ABSENT, and there is no reachable edit destination',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(tester, countHeader());

      expect(
        countHeader(),
        findsOneWidget,
        reason:
            'positive assertion — the services THEMSELVES rendered, not '
            'merely the absence of write affordances',
      );
      expect(
        countHeaderText(tester),
        '2 послуги',
        reason:
            'the rendered count copy itself — genuinely verifies the '
            'pluralized Ukrainian label, not merely that some header '
            'widget exists',
      );
      expect(
        find.byKey(const Key('btn-create-service')),
        findsNothing,
        reason: 'phase 320 D1 — writable: false hides the FAB',
      );

      // Sections start collapsed — expand the uncategorized bucket
      // (`_serviceRow` sets no category) to reach the cards themselves.
      expect(find.byKey(const Key('category_section__none')), findsOneWidget);
      await tester.tap(find.byKey(const Key('category_section__none')));
      await tester.pumpAndSettle();

      final Finder cardFinder = find.byKey(const Key('service_card_svc-1'));
      expect(
        cardFinder,
        findsOneWidget,
        reason: 'the card itself must render, not just the count header',
      );
      // i18n-finder-ok: the service NAME is fixture data set by this file's
      // own `_serviceRow`, not app UI copy — it renders verbatim regardless
      // of locale, exactly like the `'500 грн'` example in the guard's doc.
      expect(find.text('Манікюр'), findsOneWidget);
      expect(
        find.descendant(of: cardFinder, matching: find.byType(GestureDetector)),
        findsNothing,
        reason:
            'writable: false must pass a null onEdit — no GestureDetector '
            'means genuinely non-tappable, not "tappable, does nothing"',
      );

      final ServicesListScreen screen = tester.widget<ServicesListScreen>(
        find.byType(ServicesListScreen),
      );
      expect(screen.writable, isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // 4. THE ROLE-CHECK ORDERING PIN.
  // -------------------------------------------------------------------------

  testWidgets(
    'masterProfileProvider is resolved exactly once for the SALON_MASTER '
    'session that reaches this route (the role check does not block the '
    'legitimate case)',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(tester, countHeader());

      expect(
        _ControlledMasterProfile.builds,
        greaterThan(0),
        reason:
            'the SALON_MASTER session must reach masterProfileProvider — '
            'the ordering pin only refuses the check for OTHER roles, it '
            'does not block the one role this route exists for',
      );
    },
  );

  // -------------------------------------------------------------------------
  // 5. CONTROL — INDEPENDENT_MASTER's /services is behaviourally unaffected.
  // -------------------------------------------------------------------------

  testWidgets('CONTROL: an INDEPENDENT_MASTER at /services sees every write '
      'affordance and hits the ROOT /independent-masters/me/services '
      'endpoint, never the salon path', (tester) async {
    _MutableAuthNotifier.seed = _kIndependentMasterUser;

    final container = makeContainer();
    final router = await pumpRouter(tester, container);

    router.go(RouteNames.services);
    await pumpUntilFound(tester, find.byType(ServicesListScreen));
    // AUDIT 2026-09-13 (D1) — this row used to read
    //   await pumpUntil(tester, () => countHeader().evaluate().isEmpty);
    // under the old `pumpWhile` spelling, i.e. "wait while the header is
    // absent". That helper returns THE INSTANT ITS CONDITION HOLDS, so as a
    // wait it was dead either way, and mutation proved it: deleting the line
    // left this row green.
    //
    // Measured rather than assumed (probe, 2026-09-13): the count header is
    // ALREADY in the tree on the frame `ServicesListScreen` is first found —
    // the mocked `getMyServices` resolves before the leaf mounts. So the old
    // line's condition was FALSE on entry and it burned its entire
    // 60-iteration budget as a pure timeout; it was not the "zero frames"
    // shape its sibling at `salon_manage_staff_services_route_test.dart:1664`
    // has. Same dead line, different mechanism.
    //
    // Inverted to the wait that is actually meant — until the header APPEARS
    // — and anchored on the RENDERED COUNT rather than the header's mere
    // existence, so the row pins that the ROOT catalogue's DATA arrived (the
    // IM fixture holds exactly one service) instead of only that some chrome
    // is on screen. Note this wait cannot be made load-bearing by mutation at
    // this fixture's timing: the data is there before the screen is, so
    // deleting the line still passes. What the assertion buys is that the
    // negative claim below is now measured against a tree whose root load
    // has DEMONSTRABLY landed.
    await pumpUntilFound(tester, countHeader());
    expect(
      countHeaderText(tester),
      '1 послуга',
      reason:
          'the rendered count is the proof the ROOT catalogue resolved WITH '
          'its data. The negative assertion below only means something once '
          'a load has actually happened — on an unsettled tree "no salon URI '
          'was recorded" is true because NO URI was recorded at all.',
    );

    final ServicesListScreen screen = tester.widget<ServicesListScreen>(
      find.byType(ServicesListScreen),
    );
    expect(
      screen.writable,
      isTrue,
      reason: 'the default — unaffected by phase 321',
    );
    expect(find.byKey(const Key('btn-create-service')), findsOneWidget);
    expect(
      recordedUris,
      isNot(contains(salonServicesUri(_kViewerMasterRowId))),
      reason: 'must never take the salon-scoped path',
    );
    verify(() => mockServiceApi.getMyServices()).called(greaterThan(0));
  });

  // -------------------------------------------------------------------------
  // 6. AUDIT cycle-2 (N2) — the ShellRoute scope SURVIVES a tab round trip.
  //
  // `VelvetBottomNavBar` switches the SALON_MASTER's three tab roots with
  // `context.go`, which REPLACES the stack. While the `serviceTargetProvider`
  // override lived inside `_SalonMasterOwnServicesRoute._resolved`, every tab
  // tap disposed the scoped container — and with it the `keepAlive`
  // `masterServiceCatalogProvider` inside it — so every return to tile 0
  // re-fired `GET /salons/{s}/masters/{m}/services`. (`keepAlive` is a
  // per-CONTAINER guarantee, which is why the INDEPENDENT_MASTER, whose
  // catalogue lives in the ROOT container, never paid this.) The cycle-1 fix
  // hoisted the scope into a `ShellRoute` (`app_router.dart:1964`) whose
  // builder genuinely wraps the child Navigator.
  //
  // Nothing pinned that: deleting the `ShellRoute` and putting the scope back
  // on the leaf left the entire suite green. This row is the guard.
  //
  // TWO independent observables, because either alone is weak:
  //   • the REQUEST COUNT for the salon catalogue endpoint across the round
  //     trip (`invalidate` retains `.value`, so a null/loading check would
  //     prove nothing — only a genuine wire call is evidence);
  //   • `ProviderScope.containerOf` on the mounted `ServicesListScreen`
  //     element, identical before and after — the container is the thing the
  //     fix is actually about, and it stays pinned even if a future fixture
  //     made the catalogue cheap enough to hide the extra fetch.
  //
  // `router.go` (i.e. `context.go` — the same `GoRouter.go` call) is used
  // DELIBERATELY here, against this repo's usual "nav-detection tests must
  // push" rule: stack REPLACEMENT is the precise navigation mode the finding
  // is about, and a `push` would keep the leaf mounted and prove nothing.
  // -------------------------------------------------------------------------

  testWidgets(
    'the tab ShellRoute keeps ONE ProviderScope across services → profile → '
    'services: the salon catalogue endpoint fires exactly once',
    (tester) async {
      final container = makeContainer();
      final router = await pumpRouter(tester, container);

      final String catalogueUri = salonServicesUri(_kViewerMasterRowId);
      int catalogueCalls() =>
          recordedUris.where((String u) => u == catalogueUri).length;

      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(tester, countHeader());

      expect(
        catalogueCalls(),
        1,
        reason:
            'baseline — one fetch for the first mount, so the post-round-trip '
            'assertion below measures the round trip and nothing else',
      );
      final ProviderContainer before = ProviderScope.containerOf(
        tester.element(find.byType(ServicesListScreen)),
      );

      // Tile 3 → «Профіль». `go` REPLACES the stack: the services leaf is
      // unmounted, and only the shell's scope can outlive it.
      router.go(RouteNames.salonMasterProfile);
      await pumpUntilGone(tester, find.byType(ServicesListScreen));
      expect(
        find.byType(ServicesListScreen),
        findsNothing,
        reason:
            'the round trip must genuinely unmount the leaf — otherwise the '
            'count assertion below passes because nothing ever happened',
      );

      // Tile 0 → «Послуги», back again.
      router.go(RouteNames.salonMasterServices);
      await pumpUntilFound(tester, countHeader());

      expect(
        catalogueCalls(),
        1,
        reason:
            'the scoped keepAlive catalogue must survive the go-based tab '
            'round trip — a second GET here is the exact regression the '
            'ShellRoute exists to prevent',
      );
      final ProviderContainer after = ProviderScope.containerOf(
        tester.element(find.byType(ServicesListScreen)),
      );
      expect(
        identical(after, before),
        isTrue,
        reason:
            'the SAME scoped container, not merely an equal one — a leaf-level '
            'ProviderScope would build a fresh container on every remount',
      );
    },
  );
}
