// Phase 2.19 — Widget tests for [RegisterStep3Screen] — VelvetTouch redesign.
//
// Design source of truth:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/address_screen.dart
//
// Key changes from the glassmorphism version (Phase 2.19):
//   - Route builder: RegisterStep3Screen now wraps its own AuthScaffold
//     (Scaffold + scroll). The harness GoRoute passes it directly.
//   - Key renames:
//       Key('field-street')            → ValueKey<String>('address_street')
//       Key('field-building')          → ValueKey<String>('address_building')
//       Key('field-note')              → ValueKey<String>('address_note')
//       Key('btn-skip-step3')          → ValueKey<String>('address_skip')
//       Key('btn-save-step3')          → ValueKey<String>('address_submit')  (CLIENT)
//       Key('btn-save-continue-step3') → ValueKey<String>('address_submit')  (MASTER/OWNER)
//   - Skip affordance is now a GestureDetector (was InkWell).
//   - Layout: SubStepIndicator is nested inside a NeumorphicCard (Test 1b probe
//     path updated).
//
// Covered scenarios (unchanged):
//   1. CLIENT renders 3 picker rows + split CTA, NO street/building/note.
//   1b. CLIENT "Пропустити" link renders with maxLines == 1.
//   2. MASTER renders 3 picker rows + street/building/note + single CTA.
//   3. OWNER renders 3 picker rows + street/building/note + single CTA.
//   4. CLIENT "Пропустити" → register → /verification (no provider save).
//   5. MASTER full submit → register, stash locality in draft → /verification.
//   6. OWNER full submit → register, stash salon locality → /verification.
//   7. City-without-districts → District disabled; submit OK; draft districtId null.
//   8. City-with-districts, district unpicked → submit blocked; "Оберіть район"
//      under the DISTRICT row.
//   9. (Defect 2) CLIENT Save error → Skip proves _submitting resets.
//   10. Register failure → snackbar, no profile-save, no navigate.
//   11. Successful register clears draft password before /verification.

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
      // Phase 2.19: RegisterStep3Screen now provides its own AuthScaffold
      // (Scaffold + scroll). No outer wrapper needed in the test harness.
      builder: (context, state) => const RegisterStep3Screen(),
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

      // Phase 2.19 keys: CLIENT split CTA.
      expect(
        find.byKey(const ValueKey<String>('address_skip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('address_submit')),
        findsOneWidget,
      );

      // No address fields for CLIENT.
      expect(
        find.byKey(const ValueKey<String>('address_street')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('address_building')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('address_note')), findsNothing);
      expect(find.byKey(const Key('step3-address-divider')), findsNothing);
    },
  );

  // ── 1b. CLIENT skip-button label stays single-line (overflow guard) ───────
  testWidgets('1b. CLIENT "Пропустити" link renders with maxLines == 1', (
    tester,
  ) async {
    final container = _container(
      role: UserRole.client,
      authRepo: _MockAuthRepository(),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    // Phase 2.19: skip affordance is a GestureDetector wrapping a Text.
    final skipText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('address_skip')),
        matching: find.byType(Text),
      ),
    );
    expect(skipText.maxLines, 1);
  });

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
    expect(
      find.byKey(const ValueKey<String>('address_street')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('address_building')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('address_note')), findsOneWidget);
    expect(find.byKey(const Key('step3-address-divider')), findsOneWidget);

    // Single CTA, no split.
    expect(
      find.byKey(const ValueKey<String>('address_submit')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('address_skip')), findsNothing);
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

    expect(
      find.byKey(const ValueKey<String>('address_street')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('address_building')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('address_note')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('address_submit')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('address_skip')), findsNothing);
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

    await tester.tap(find.byKey(const ValueKey<String>('address_skip')));
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

  // ── 5. MASTER full submit → register, stash locality, navigate ────────────
  // Defect 8 — provider save is DEFERRED to VerificationScreen, so Step 3
  // must NOT call updateLocality.
  testWidgets('5. MASTER submit → register, stash draft locality, navigates', (
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
      find.byKey(const ValueKey<String>('address_street')),
      'вул. Тестова',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('address_building')),
      '12А',
    );
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey<String>('address_submit'));

    verify(
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
    ).called(1);
    // Auth-required save MUST NOT run on Step 3 (Defect 8).
    verifyNever(
      () => masterRepo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    );
    // Locality/address stashed in the keepAlive draft for post-verification save.
    final draft = container.read(registerDraftProvider)!;
    expect(draft.cityId, 'c1');
    expect(draft.districtId, 'd1');
    expect(draft.street, 'вул. Тестова');
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 6. OWNER full submit → register, stash salon locality, navigate ───────
  // POST /salons deferred to VerificationScreen; Step 3 must not call
  // salon.create.
  testWidgets('6. OWNER submit → register, stash draft locality, navigates', (
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
      find.byKey(const ValueKey<String>('address_street')),
      'вул. Тестова',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('address_building')),
      '8',
    );
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey<String>('address_submit'));

    verify(
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
    ).called(1);
    // POST /salons MUST NOT run on Step 3 (Defect 8).
    verifyNever(() => salonRepo.create(dto: any(named: 'dto')));
    final draft = container.read(registerDraftProvider)!;
    expect(draft.cityId, 'c1');
    expect(draft.districtId, 'd1');
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 7. City without districts → District disabled + helper; submit OK ─────
  testWidgets('7. City-without-districts → submit OK, draft districtId null', (
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

    // District row is disabled for a leaf city.
    final ip = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byKey(const Key('locality_row_district')),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ip.ignoring, isTrue);

    // Defect 5 — explanatory helper caption.
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('locality-cascade'))),
    );
    expect(find.text(l10n.localityDistrictNoneHelper), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('address_street')),
      'вул. Тестова',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('address_building')),
      '5',
    );
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey<String>('address_submit'));

    final draft = container.read(registerDraftProvider)!;
    expect(draft.cityId, 'c2');
    expect(draft.districtId, isNull);
    verifyNever(
      () => masterRepo.updateLocality(
        cityId: any(named: 'cityId'),
        districtId: any(named: 'districtId'),
        street: any(named: 'street'),
        buildingNo: any(named: 'buildingNo'),
        locationNote: any(named: 'locationNote'),
      ),
    );
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
      find.byKey(const ValueKey<String>('address_street')),
      'вул. Тестова',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('address_building')),
      '12',
    );
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey<String>('address_submit'));

    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('locality-cascade'))),
    );
    // Defect 7 — the "Оберіть район" error must render under the DISTRICT row.
    final districtError = find.descendant(
      of: find.byKey(const Key('locality_row_district')),
      matching: find.byKey(const Key('locality_tap_row_error')),
    );
    expect(districtError, findsOneWidget);
    expect(
      tester.widget<Text>(districtError).data,
      l10n.errLocalityDistrictRequired,
    );
    // Error is NOT attached to the oblast/city rows.
    expect(
      find.descendant(
        of: find.byKey(const Key('locality_row_oblast')),
        matching: find.byKey(const Key('locality_tap_row_error')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('locality_row_city')),
        matching: find.byKey(const Key('locality_tap_row_error')),
      ),
      findsNothing,
    );
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

  // ── 9. (Defect 2) CLIENT Save→register error→Skip — _submitting resets ────
  // Proves the finally block re-enables both CTAs even on a register failure.
  // GestureDetector.onTap is checked (was InkWell.onTap in the old version).
  testWidgets('9. CLIENT Save error then Skip — CTAs not stuck disabled', (
    tester,
  ) async {
    final authRepo = _MockAuthRepository();
    var call = 0;
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
    ).thenAnswer((_) async {
      call++;
      // First Save fails; second (Skip) succeeds.
      if (call == 1) throw const NetworkFailure();
      return const RegisterResult.verificationRequired(email: 'a@b.com');
    });

    final container = _container(role: UserRole.client, authRepo: authRepo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pumpAndSettle();

    // First tap Save → register fails → error snackbar, still on Step 3.
    await _tap(tester, const ValueKey<String>('address_submit'));
    expect(find.byKey(const Key('step3-snackbar')), findsOneWidget);
    expect(find.textContaining('verification:'), findsNothing);

    // Phase 2.19: skip is a GestureDetector; onTap must be non-null to prove
    // _submitting reset in the finally block.
    final skipGestureDetector = tester.widget<GestureDetector>(
      find.byKey(const ValueKey<String>('address_skip')),
    );
    expect(skipGestureDetector.onTap, isNotNull);

    // Dismiss the error snackbar so its overlay no longer obscures the pinned
    // bottomBar skip button (the snackbar renders above the scaffold content in
    // the test viewport at the same Y coordinate as bottomBar).
    final scaffoldMessenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger),
    );
    scaffoldMessenger.clearSnackBars();
    await tester.pumpAndSettle();

    // Tapping Skip now succeeds and navigates.
    await _tap(tester, const ValueKey<String>('address_skip'));
    expect(find.text('verification:a@b.com'), findsOneWidget);
  });

  // ── 10. Register FAILURE → snackbar, no profile-save, no navigation ───────
  testWidgets(
    '10. register failure → error snackbar, no updateLocality, no navigate',
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
        find.byKey(const ValueKey<String>('address_street')),
        'вул. Тестова',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('address_building')),
        '12',
      );
      await tester.pumpAndSettle();

      await _tap(tester, const ValueKey<String>('address_submit'));

      expect(find.byKey(const Key('step3-snackbar')), findsOneWidget);
      verifyNever(
        () => masterRepo.updateLocality(
          cityId: any(named: 'cityId'),
          districtId: any(named: 'districtId'),
          street: any(named: 'street'),
          buildingNo: any(named: 'buildingNo'),
          locationNote: any(named: 'locationNote'),
        ),
      );
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

      // Sanity: seeded draft holds the plaintext password before submit.
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
        find.byKey(const ValueKey<String>('address_street')),
        'вул. Тестова',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('address_building')),
        '12',
      );
      await tester.pumpAndSettle();

      await _tap(tester, const ValueKey<String>('address_submit'));

      expect(find.text('verification:a@b.com'), findsOneWidget);
      final draft = container.read(registerDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.password, isEmpty);
      expect(draft.confirmPassword, isEmpty);
      expect(draft.email, equals('a@b.com'));
    },
  );
}
