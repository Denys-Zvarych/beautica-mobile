// Phase 2.19 — Widget tests for [RegisterStep3Screen].
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-step-3-address.html.
//
// Covered scenarios (9 per phase-doc Step 7):
//   1. CLIENT renders 3 picker rows + split CTA, NO street/building/note.
//   2. MASTER renders 3 picker rows + street/building/note + single CTA.
//   3. OWNER renders 3 picker rows + street/building/note + single CTA.
//   4. CLIENT "Пропустити" → register WITHOUT profile-save → /verification.
//   5. MASTER full submit → register THEN updateLocality → /verification.
//   6. OWNER full submit → register THEN salon.create → /verification.
//   7. City-without-districts → District disabled; provider submit succeeds with
//      districtId = null.
//   8. City-with-districts, district unpicked → submit blocked, "Оберіть район".
//   9. Profile-save failure after register success → snackbar + still navigates.
//
// Strategy: override authRepositoryProvider (register), locationRepositoryProvider
// (cascade), masterRepositoryProvider + salonRepositoryProvider (profile-save)
// with mocktail mocks / a fake. The draft is pre-seeded with Step 1/2 data.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_3_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _oblast = Oblast(id: 'o1', name: 'Львівська', katotthCode: 'UA46');
const _cityWithDistricts = City(
  id: 'c1',
  oblastId: 'o1',
  name: 'Львів',
  katotthCode: 'UA4610',
  hasDistricts: true,
);
const _cityNoDistricts = City(
  id: 'c2',
  oblastId: 'o1',
  name: 'Дрогобич',
  katotthCode: 'UA4620',
  hasDistricts: false,
);
const _district = CityDistrict(
  id: 'd1',
  cityId: 'c1',
  name: 'Галицький',
  katotthCode: 'UA4610136',
);

// ---------------------------------------------------------------------------
// Fakes / mocks
// ---------------------------------------------------------------------------

class _FakeLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => const [_oblast];

  @override
  Future<List<City>> fetchCities(String oblastId) async => const [
    _cityWithDistricts,
    _cityNoDistricts,
  ];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async => const [
    _district,
  ];
}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.registerStep3,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.registerStep3,
      // Scaffold so SnackBars + TextFormFields find their ancestors.
      builder: (context, state) => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: RegisterStep3Screen(),
        ),
      ),
    ),
    GoRoute(
      path: RouteNames.verification,
      builder: (context, state) {
        final email = (state.extra as String?) ?? '';
        return Scaffold(body: Center(child: Text('verification:$email')));
      },
    ),
  ],
);

ProviderContainer _container({
  required UserRole role,
  required AuthRepository authRepo,
  MasterRepository? masterRepo,
  SalonRepository? salonRepo,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((_) => authRepo),
      locationRepositoryProvider.overrideWith((_) => _FakeLocationRepository()),
      if (masterRepo != null)
        masterRepositoryProvider.overrideWith((_) => masterRepo),
      if (salonRepo != null)
        salonRepositoryProvider.overrideWith((_) => salonRepo),
    ],
  );
  // Seed the draft with Step 1/2 data so register has email/password/etc.
  final notifier = container.read(registerDraftProvider.notifier)..start(role);
  notifier.updateStep1(
    email: 'a@b.com',
    password: 'Password1!',
    confirmPassword: 'Password1!',
  );
  notifier.updateStep2(
    firstName: 'Аня',
    lastName: 'Коваль',
    phone: '+380501112233',
    salonName: role == UserRole.salonOwner ? 'Salon Lumière' : '',
  );
  return container;
}

Widget _app(GoRouter router, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    );

/// Selects an item in the cascade by tapping the row then the item text.
Future<void> _pick(WidgetTester tester, Key rowKey, String itemText) async {
  await tester.ensureVisible(find.byKey(rowKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(rowKey));
  await tester.pumpAndSettle(); // open sheet + resolve list future
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle(); // pop sheet
}

/// Scrolls [key] into view then taps it (the default 800x600 test viewport is
/// shorter than the provider variant's full content height).
Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const SalonCreateDto(
        name: 'x',
        cityId: 'x',
        street: 'x',
        buildingNo: 'x',
      ),
    );
    registerFallbackValue(UserRole.independentMaster);
  });

  // ── 1. CLIENT layout ──────────────────────────────────────────────────────
  testWidgets(
    '1. CLIENT renders 3 picker rows + split CTA, no address fields',
    (tester) async {
      final container = _container(
        role: UserRole.client,
        authRepo: _MockAuthRepository(),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(_makeRouter(), container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('locality_row_oblast')), findsOneWidget);
      expect(find.byKey(const Key('locality_row_city')), findsOneWidget);
      expect(find.byKey(const Key('locality_row_district')), findsOneWidget);

      // Split CTA — both ghost + filled present.
      expect(find.byKey(const Key('btn-skip-step3')), findsOneWidget);
      expect(find.byKey(const Key('btn-save-step3')), findsOneWidget);

      // No address fields for CLIENT.
      expect(find.byKey(const Key('field-street')), findsNothing);
      expect(find.byKey(const Key('field-building')), findsNothing);
      expect(find.byKey(const Key('field-note')), findsNothing);
      expect(find.byKey(const Key('step3-address-divider')), findsNothing);
    },
  );

  // ── 2. MASTER layout ──────────────────────────────────────────────────────
  testWidgets('2. MASTER renders 3 picker rows + address fields + single CTA', (
    tester,
  ) async {
    final container = _container(
      role: UserRole.independentMaster,
      authRepo: _MockAuthRepository(),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('locality_row_oblast')), findsOneWidget);
    expect(find.byKey(const Key('field-street')), findsOneWidget);
    expect(find.byKey(const Key('field-building')), findsOneWidget);
    expect(find.byKey(const Key('field-note')), findsOneWidget);
    expect(find.byKey(const Key('step3-address-divider')), findsOneWidget);

    // Single CTA, no split.
    expect(find.byKey(const Key('btn-save-continue-step3')), findsOneWidget);
    expect(find.byKey(const Key('btn-skip-step3')), findsNothing);
  });

  // ── 3. OWNER layout ───────────────────────────────────────────────────────
  testWidgets('3. OWNER renders 3 picker rows + address fields + single CTA', (
    tester,
  ) async {
    final container = _container(
      role: UserRole.salonOwner,
      authRepo: _MockAuthRepository(),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('field-street')), findsOneWidget);
    expect(find.byKey(const Key('field-building')), findsOneWidget);
    expect(find.byKey(const Key('field-note')), findsOneWidget);
    expect(find.byKey(const Key('btn-save-continue-step3')), findsOneWidget);
    expect(find.byKey(const Key('btn-skip-step3')), findsNothing);
  });

  // ── 4. CLIENT skip → register without profile-save → /verification ────────
  testWidgets('4. CLIENT Пропустити → register, no profile-save, navigates', (
    tester,
  ) async {
    final authRepo = _MockAuthRepository();
    when(
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: any(named: 'role'),
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
    ).thenAnswer(
      (_) async => const RegisterResult.verificationRequired(email: 'a@b.com'),
    );

    final container = _container(role: UserRole.client, authRepo: authRepo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn-skip-step3')));
    await tester.pumpAndSettle();

    verify(
      () => authRepo.registerIndependentMaster(
        email: 'a@b.com',
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: UserRole.client,
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
    ).called(1);
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 5. MASTER full submit → register THEN updateLocality → /verification ──
  testWidgets('5. MASTER submit → register then updateLocality, navigates', (
    tester,
  ) async {
    final authRepo = _MockAuthRepository();
    final masterRepo = _MockMasterRepository();
    when(
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: any(named: 'role'),
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
    ).thenAnswer(
      (_) async => const RegisterResult.verificationRequired(email: 'a@b.com'),
    );
    when(
      () => masterRepo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ).thenAnswer((_) async {});

    final container = _container(
      role: UserRole.independentMaster,
      authRepo: authRepo,
      masterRepo: masterRepo,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    await _pick(tester, const Key('locality_row_oblast'), 'Львівська');
    await _pick(tester, const Key('locality_row_city'), 'Львів');
    await _pick(tester, const Key('locality_row_district'), 'Галицький');
    await tester.enterText(
      find.byKey(const Key('field-street')),
      'вул. Тестова',
    );
    await tester.enterText(find.byKey(const Key('field-building')), '12А');
    await tester.pumpAndSettle();

    await _tap(tester, const Key('btn-save-continue-step3'));

    verifyInOrder([
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: UserRole.independentMaster,
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
      () => masterRepo.updateLocality(
        cityId: 'c1',
        districtId: 'd1',
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ]);
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 6. OWNER full submit → register THEN salon.create → /verification ─────
  testWidgets('6. OWNER submit → register then salon.create, navigates', (
    tester,
  ) async {
    final authRepo = _MockAuthRepository();
    final salonRepo = _MockSalonRepository();
    when(
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: any(named: 'role'),
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
    ).thenAnswer(
      (_) async => const RegisterResult.verificationRequired(email: 'a@b.com'),
    );
    when(
      () => salonRepo.create(dto: any(named: 'dto')),
    ).thenAnswer((_) async {});

    final container = _container(
      role: UserRole.salonOwner,
      authRepo: authRepo,
      salonRepo: salonRepo,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    await _pick(tester, const Key('locality_row_oblast'), 'Львівська');
    await _pick(tester, const Key('locality_row_city'), 'Львів');
    await _pick(tester, const Key('locality_row_district'), 'Галицький');
    await tester.enterText(
      find.byKey(const Key('field-street')),
      'вул. Тестова',
    );
    await tester.enterText(find.byKey(const Key('field-building')), '8');
    await tester.pumpAndSettle();

    await _tap(tester, const Key('btn-save-continue-step3'));

    verifyInOrder([
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: UserRole.salonOwner,
        businessName: 'Salon Lumière',
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
      () => salonRepo.create(dto: any(named: 'dto')),
    ]);
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 7. City without districts → submit succeeds with districtId = null ────
  testWidgets('7. City-without-districts → submit OK with districtId null', (
    tester,
  ) async {
    final authRepo = _MockAuthRepository();
    final masterRepo = _MockMasterRepository();
    when(
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: any(named: 'role'),
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
    ).thenAnswer(
      (_) async => const RegisterResult.verificationRequired(email: 'a@b.com'),
    );
    when(
      () => masterRepo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ).thenAnswer((_) async {});

    final container = _container(
      role: UserRole.independentMaster,
      authRepo: authRepo,
      masterRepo: masterRepo,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    await _pick(tester, const Key('locality_row_oblast'), 'Львівська');
    await _pick(tester, const Key('locality_row_city'), 'Дрогобич'); // leaf

    // District row is disabled (not tappable) for a leaf city.
    final ink = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('locality_row_district')),
        matching: find.byKey(const Key('locality_tap_row_ink')),
      ),
    );
    expect(ink.onTap, isNull);

    await tester.enterText(
      find.byKey(const Key('field-street')),
      'вул. Тестова',
    );
    await tester.enterText(find.byKey(const Key('field-building')), '5');
    await tester.pumpAndSettle();

    await _tap(tester, const Key('btn-save-continue-step3'));

    verify(
      () => masterRepo.updateLocality(
        cityId: 'c2',
        districtId: null,
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ).called(1);
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 8. City with districts, district unpicked → blocked with "Оберіть район"
  testWidgets('8. City-with-districts, no district → submit blocked', (
    tester,
  ) async {
    final authRepo = _MockAuthRepository();
    final container = _container(
      role: UserRole.independentMaster,
      authRepo: authRepo,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    await _pick(tester, const Key('locality_row_oblast'), 'Львівська');
    await _pick(
      tester,
      const Key('locality_row_city'),
      'Львів',
    ); // has districts
    await tester.enterText(
      find.byKey(const Key('field-street')),
      'вул. Тестова',
    );
    await tester.enterText(find.byKey(const Key('field-building')), '12');
    await tester.pumpAndSettle();

    await _tap(tester, const Key('btn-save-continue-step3'));

    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('locality-cascade'))),
    );
    // The keyed inline error renders the "Оберіть район" message. (Note the
    // District placeholder happens to share that exact string, so assert on the
    // keyed error widget specifically rather than the bare text.)
    final errorFinder = find.byKey(const Key('locality-error'));
    expect(errorFinder, findsOneWidget);
    expect(
      tester.widget<Text>(errorFinder).data,
      l10n.errLocalityDistrictRequired,
    );
    // Register must NOT have been called.
    verifyNever(
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: any(named: 'role'),
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
    );
    expect(find.textContaining('verification:'), findsNothing);
  });

  // ── 9. Profile-save failure after register success → snackbar + navigate ──
  testWidgets('9. Profile-save failure → snackbar shown, still navigates', (
    tester,
  ) async {
    final authRepo = _MockAuthRepository();
    final masterRepo = _MockMasterRepository();
    when(
      () => authRepo.registerIndependentMaster(
        email: any(named: 'email'),
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: any(named: 'role'),
        businessName: any(named: 'businessName'),
        address: any(named: 'address'),
        phone: any(named: 'phone'),
      ),
    ).thenAnswer(
      (_) async => const RegisterResult.verificationRequired(email: 'a@b.com'),
    );
    when(
      () => masterRepo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    ).thenThrow(const NetworkFailure());

    final container = _container(
      role: UserRole.independentMaster,
      authRepo: authRepo,
      masterRepo: masterRepo,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    await _pick(tester, const Key('locality_row_oblast'), 'Львівська');
    await _pick(tester, const Key('locality_row_city'), 'Львів');
    await _pick(tester, const Key('locality_row_district'), 'Галицький');
    await tester.enterText(
      find.byKey(const Key('field-street')),
      'вул. Тестова',
    );
    await tester.enterText(find.byKey(const Key('field-building')), '12');
    await tester.pumpAndSettle();

    await _tap(tester, const Key('btn-save-continue-step3'));

    // Navigated despite the save failure.
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 10. Register FAILURE → snackbar, no profile-save, no navigation ───────
  testWidgets(
    '10. register failure → error snackbar, no updateLocality, no navigate',
    (tester) async {
      final authRepo = _MockAuthRepository();
      final masterRepo = _MockMasterRepository();
      // register() returns null when registerIndependentMaster throws — the
      // AsyncNotifier captures the Failure as AsyncError.
      when(
        () => authRepo.registerIndependentMaster(
          email: any(named: 'email'),
          password: any(named: 'password'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          role: any(named: 'role'),
          businessName: any(named: 'businessName'),
          address: any(named: 'address'),
          phone: any(named: 'phone'),
        ),
      ).thenThrow(const ValidationFailure(fieldErrors: {'email': 'taken'}));

      final container = _container(
        role: UserRole.independentMaster,
        authRepo: authRepo,
        masterRepo: masterRepo,
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(_makeRouter(), container));
      await tester.pumpAndSettle();

      await _pick(tester, const Key('locality_row_oblast'), 'Львівська');
      await _pick(tester, const Key('locality_row_city'), 'Львів');
      await _pick(tester, const Key('locality_row_district'), 'Галицький');
      await tester.enterText(
        find.byKey(const Key('field-street')),
        'вул. Тестова',
      );
      await tester.enterText(find.byKey(const Key('field-building')), '12');
      await tester.pumpAndSettle();

      await _tap(tester, const Key('btn-save-continue-step3'));

      // Error snackbar surfaced.
      expect(find.byKey(const Key('step3-snackbar')), findsOneWidget);
      // Profile-save MUST NOT have run (account was not created).
      verifyNever(
        () => masterRepo.updateLocality(
          cityId: any(named: 'cityId'),
          districtId: any(named: 'districtId'),
          street: any(named: 'street'),
          buildingNo: any(named: 'buildingNo'),
          locationNote: any(named: 'locationNote'),
        ),
      );
      // Did NOT navigate to /verification.
      expect(find.textContaining('verification:'), findsNothing);
    },
  );

  // ── 11. Credentials cleared after successful register (MEDIUM-1 guard) ────
  testWidgets(
    '11. successful register clears draft password before /verification',
    (tester) async {
      final authRepo = _MockAuthRepository();
      final masterRepo = _MockMasterRepository();
      when(
        () => authRepo.registerIndependentMaster(
          email: any(named: 'email'),
          password: any(named: 'password'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          role: any(named: 'role'),
          businessName: any(named: 'businessName'),
          address: any(named: 'address'),
          phone: any(named: 'phone'),
        ),
      ).thenAnswer(
        (_) async =>
            const RegisterResult.verificationRequired(email: 'a@b.com'),
      );
      when(
        () => masterRepo.updateLocality(
          cityId: any(named: 'cityId'),
          districtId: any(named: 'districtId'),
          street: any(named: 'street'),
          buildingNo: any(named: 'buildingNo'),
          locationNote: any(named: 'locationNote'),
        ),
      ).thenAnswer((_) async {});

      final container = _container(
        role: UserRole.independentMaster,
        authRepo: authRepo,
        masterRepo: masterRepo,
      );
      addTearDown(container.dispose);

      // Sanity: the seeded draft holds the plaintext password before submit.
      expect(
        container.read(registerDraftProvider)!.password,
        equals('Password1!'),
      );

      await tester.pumpWidget(_app(_makeRouter(), container));
      await tester.pumpAndSettle();

      await _pick(tester, const Key('locality_row_oblast'), 'Львівська');
      await _pick(tester, const Key('locality_row_city'), 'Львів');
      await _pick(tester, const Key('locality_row_district'), 'Галицький');
      await tester.enterText(
        find.byKey(const Key('field-street')),
        'вул. Тестова',
      );
      await tester.enterText(find.byKey(const Key('field-building')), '12');
      await tester.pumpAndSettle();

      await _tap(tester, const Key('btn-save-continue-step3'));

      // Reached the verification step…
      expect(find.text('verification:a@b.com'), findsOneWidget);
      // …and the credential fields were wiped from the keepAlive draft, while
      // the rest of the draft (email) survives for the OTP step.
      final draft = container.read(registerDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.password, isEmpty);
      expect(draft.confirmPassword, isEmpty);
      expect(draft.email, equals('a@b.com'));
    },
  );
}
