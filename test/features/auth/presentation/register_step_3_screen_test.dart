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
// - Layout: SubStepIndicator and its NeumorphicCard wrapper removed; SizedBox(sm) spacer added between sub-text and LocalityCascade.
//
// Covered scenarios:
//   1.   CLIENT renders 3 picker rows + split CTA, NO street/building/note.
//   1b.  CLIENT "Пропустити" link renders with maxLines == 1.
//   2.   MASTER renders 3 picker rows + street/building/note + single CTA.
//   3.   OWNER renders 3 picker rows + street/building/note + single CTA.
//   4.   CLIENT "Пропустити" → register → /verification (no provider save).
//   5.   MASTER full submit → register, stash locality in draft → /verification.
//   6.   OWNER full submit → register, stash salon locality → /verification.
//   7.   City-without-districts → District disabled; submit OK; draft districtId null.
//   8.   City-with-districts, district unpicked → submit blocked; "Оберіть район"
//        under the DISTRICT row.
//   9.   (Defect 2) CLIENT Save error → Skip proves _submitting resets.
//   10.  Register failure → snackbar, no profile-save, no navigate.
//   11.  Successful register clears draft password before /verification.
//   12.  auth_scaffold_back navigates to /register/step-2 without firing register POST.
//   13.  Already-registered guard: draft.password empty → skip register() → /verification.
//   14.  initState prefetch: oblastListProvider is read on first frame.
//   15.  MASTER submit with empty street → street inline errorText.
//   (A). EmailAlreadyRegisteredFailure (409) renders inline banner + Sign In CTA.
//   (B). verificationCardDesc resolves to the honest "Ми надіслали" copy in uk.
//   (C). location_on_outlined icon tile renders at top of Step 3.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
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
import 'package:beautica_mobile/shared/validators/server_field_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

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

class _SpyLocationRepository extends _FakeLocationRepository {
  int fetchOblastsCallCount = 0;

  @override
  Future<List<Oblast>> fetchOblasts() {
    fetchOblastsCallCount++;
    return super.fetchOblasts();
  }
}

/// Simulates a location repository whose fetchOblasts() throws NetworkFailure.
/// Used to verify the Step 3 prefetch error path — the screen must not crash
/// when the oblast warm-up fails (error state rendered instead of picker data).
class _FailingLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => throw const NetworkFailure();

  @override
  Future<List<City>> fetchCities(String oblastId) async => const [];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async => const [];
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
    // /login is the navigation target of the EmailAlreadyRegisteredFailure
    // banner CTA — used by the 409+EMAIL_ALREADY_REGISTERED test.
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login-screen'))),
    ),
  ],
);

ProviderContainer _container({
  required UserRole role,
  required AuthRepository authRepo,
  MasterRepository? masterRepo,
  SalonRepository? salonRepo,
  LocationRepository? locationRepo,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((_) => authRepo),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      locationRepositoryProvider.overrideWith(
        (_) => locationRepo ?? _FakeLocationRepository(),
      ),
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

  // ── 10b. Register ValidationFailure with field map → field-named banner ───
  //
  // The offending fields (firstName/phone) live on Step 2, so a generic banner
  // gives the user no clue what to fix. The screen maps fieldErrors through
  // buildFieldErrorBanner: each line is "<localized field name>: <server msg>".
  testWidgets(
    '10b. register ValidationFailure with field map → snackbar names the '
    'failed fields inline (not the generic banner)',
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
      ).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{
            'firstName': 'Занадто коротке',
            'phone': 'Невірний формат',
          },
        ),
      );

      final container = _container(
        role: UserRole.independentMaster,
        authRepo: authRepo,
        masterRepo: masterRepo,
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(_makeRouter(), container));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));

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

      // The snackbar carries the field-named banner lines, NOT the generic
      // errValidation copy.
      expect(find.byKey(const Key('step3-snackbar')), findsOneWidget);
      final expected = buildFieldErrorBanner(const <String, String>{
        'firstName': 'Занадто коротке',
        'phone': 'Невірний формат',
      }, l10n)!;
      expect(find.text(expected), findsOneWidget);
      expect(find.text(l10n.errValidation), findsNothing);
      // No navigation.
      expect(find.textContaining('verification:'), findsNothing);
    },
  );

  // ── 10c. Register ValidationFailure, EMPTY map + serverMessage → fallback ──
  //
  // When the backend returns a 400 with no usable field map, the banner builder
  // returns null and the screen falls back to the top-level serverMessage (then
  // the generic string). Guards the "dead Save with no feedback" regression.
  testWidgets(
    '10c. register ValidationFailure with empty fieldErrors falls back to '
    'serverMessage in the snackbar',
    (tester) async {
      final authRepo = _MockAuthRepository();
      final masterRepo = _MockMasterRepository();
      const serverMsg = 'Реєстрація тимчасово недоступна';
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
      ).thenThrow(
        const ValidationFailure(
          fieldErrors: <String, String>{},
          serverMessage: serverMsg,
        ),
      );

      final container = _container(
        role: UserRole.independentMaster,
        authRepo: authRepo,
        masterRepo: masterRepo,
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(_makeRouter(), container));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));

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
      // Server message wins over the generic errValidation fallback.
      expect(find.text(serverMsg), findsOneWidget);
      expect(find.text(l10n.errValidation), findsNothing);
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

  // ── 12. auth_scaffold_back navigates to /register/step-2 (GROUP A) ────────
  //
  // GROUP A regression: Step 3 now delegates back-navigation entirely to
  // AuthScaffold (key 'auth_scaffold_back'). There is no separate bottom-row
  // back affordance. Tapping auth_scaffold_back must navigate to
  // /register/step-2 and MUST NOT fire the register POST.
  testWidgets('12. auth_scaffold_back is present on Step 3 and navigates to '
      '/register/step-2 without firing the register POST', (tester) async {
    final authRepo = _MockAuthRepository();

    // Step-2 stub in the router.
    final router = GoRouter(
      initialLocation: RouteNames.registerStep3,
      redirect: (context, state) => null,
      routes: [
        GoRoute(
          path: RouteNames.registerStep3,
          builder: (context, state) => const RegisterStep3Screen(),
        ),
        GoRoute(
          path: RouteNames.registerStep2,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('step-2'))),
        ),
        GoRoute(
          path: RouteNames.verification,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('verification'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = _container(
      role: UserRole.independentMaster,
      authRepo: authRepo,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(router, container));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('auth_scaffold_back')),
      findsOneWidget,
      reason:
          'Step 3 wraps its own AuthScaffold — auth_scaffold_back must be '
          'rendered',
    );

    await tester.tap(find.byKey(const ValueKey<String>('auth_scaffold_back')));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.fullPath,
      equals(RouteNames.registerStep2),
      reason: 'auth_scaffold_back on Step 3 must navigate to /register/step-2',
    );
    expect(find.text('step-2'), findsOneWidget);

    // No registration POST must fire on a back-tap.
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
  });

  // ── 13. Already-registered guard (draft.password.isEmpty → /verification) ──
  //
  // Phase 2.19 bug fix: if the user successfully registered, navigated to the
  // verification screen, then pressed back and re-tapped "Зберегти і продовжити",
  // the screen must skip the duplicate register() call and go directly to
  // /verification using the email already stored in the draft.
  //
  // The guard is triggered by draft.password being empty (set by
  // clearCredentials() after the first successful register call).
  testWidgets(
    '13. already-registered guard: when draft.password is empty, tapping '
    'submit skips register() and navigates straight to /verification',
    (tester) async {
      final authRepo = _MockAuthRepository();

      final router = GoRouter(
        initialLocation: RouteNames.registerStep3,
        redirect: (context, state) => null,
        routes: [
          GoRoute(
            path: RouteNames.registerStep3,
            builder: (context, state) => const RegisterStep3Screen(),
          ),
          GoRoute(
            path: RouteNames.verification,
            builder: (context, state) {
              final email = (state.extra as String?) ?? '';
              return Scaffold(body: Center(child: Text('verification:$email')));
            },
          ),
          GoRoute(
            path: RouteNames.registerStep2,
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('step-2'))),
          ),
        ],
      );
      addTearDown(router.dispose);

      final container = _container(role: UserRole.client, authRepo: authRepo);
      addTearDown(container.dispose);

      // Simulate "already registered" state: clear credentials from the draft
      // as clearCredentials() does after a successful register call.
      container.read(registerDraftProvider.notifier).clearCredentials();

      // Confirm the guard condition: password is now empty.
      expect(
        container.read(registerDraftProvider)!.password,
        isEmpty,
        reason:
            'Pre-condition: draft.password must be empty to trigger the '
            'already-registered guard',
      );
      expect(
        container.read(registerDraftProvider)!.email,
        equals('a@b.com'),
        reason:
            'Pre-condition: draft.email must be preserved after '
            'clearCredentials()',
      );

      await tester.pumpWidget(_app(router, container));
      await tester.pumpAndSettle();

      // Tap the submit button (CLIENT variant: "Зберегти").
      await _tap(tester, const ValueKey<String>('address_submit'));

      // The register POST must NOT be called — the guard short-circuits.
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

      // Navigation must go to /verification using the email from the draft.
      expect(
        find.text('verification:a@b.com'),
        findsOneWidget,
        reason:
            'already-registered guard must navigate to /verification with the '
            'email from the draft (no second register POST)',
      );
    },
  );

  // ── 14. initState prefetch — oblastListProvider is read on first frame ────
  testWidgets(
    '14. oblastListProvider is read on first frame (initState prefetch)',
    (tester) async {
      final spy = _SpyLocationRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => _MockAuthRepository()),
          locationRepositoryProvider.overrideWith((_) => spy),
        ],
      );
      final notifier = container.read(registerDraftProvider.notifier)
        ..start(UserRole.client);
      notifier.updateStep1(
        email: 'a@b.com',
        password: 'Password1!',
        confirmPassword: 'Password1!',
      );
      notifier.updateStep2(
        firstName: 'Аня',
        lastName: 'Коваль',
        phone: '+380501112233',
        salonName: '',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(_makeRouter(), container));
      // Flush the addPostFrameCallback queue first.
      await tester.pump();
      // Let the fetchOblasts Future resolve.
      await tester.pumpAndSettle();

      expect(
        spy.fetchOblastsCallCount,
        equals(1),
        reason:
            'initState addPostFrameCallback must read oblastListProvider '
            'exactly once — calling fetchOblasts() to warm the cache on '
            'first mount (not on subsequent rebuilds)',
      );
    },
  );

  // ── 15. MASTER submit with empty street → street inline errorText ──────────
  testWidgets('15. MASTER submit with locality selected but empty street → '
      'street errorText rendered inline', (tester) async {
    final authRepo = _MockAuthRepository();
    final masterRepo = _MockMasterRepository();
    final container = _container(
      role: UserRole.independentMaster,
      authRepo: authRepo,
      masterRepo: masterRepo,
    );
    addTearDown(container.dispose);

    final router = _makeRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, container));
    await tester.pumpAndSettle();

    // Select oblast → city (no districts) via cascade pickers.
    // Tap the oblast tile to open the bottom sheet.
    await tester.tap(find.byKey(const Key('locality_row_oblast')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_oblast.name));
    await tester.pumpAndSettle();

    // Tap the city tile.
    await tester.tap(find.byKey(const Key('locality_row_city')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_cityNoDistricts.name));
    await tester.pumpAndSettle();

    // Leave street empty (default) — tap submit.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('address_submit')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('address_submit')));
    await tester.pump();

    // The street field must show an inline error.
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const ValueKey<String>('address_street'))),
    );
    expect(
      find.text(l10n.errStreetRequired),
      findsWidgets,
      reason:
          'NeumorphicTextField for street must render inline errorText '
          'when street is empty on MASTER submit',
    );
  });

  // ── EmailAlreadyRegisteredFailure (409 + EMAIL_ALREADY_REGISTERED) ───────
  //
  // Backend dev mode (disclose-duplicate-registration=true) returns 409 with
  // {success:false, data:{code:"EMAIL_ALREADY_REGISTERED"}} on a duplicate-
  // email submit. Step 3 must:
  //   (a) NOT crash;
  //   (b) render an inline AuthBanner with the new l10n copy
  //       (errEmailAlreadyRegistered);
  //   (c) expose a Sign In CTA that navigates to /login WITHOUT re-running
  //       the register POST.
  //
  // Mutation: if the EmailAlreadyRegisteredFailure branch is removed from
  // _runRegisterAndSave (so the screen falls through to the generic snackbar)
  // this test fails because the banner key is absent.
  testWidgets(
    'EmailAlreadyRegisteredFailure (409) renders inline banner with new l10n '
    'copy + Sign In CTA; tapping CTA navigates to /login without '
    'auto-resubmitting the form',
    (tester) async {
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
      ).thenThrow(const EmailAlreadyRegisteredFailure());

      final router = _makeRouter();
      final container = _container(role: UserRole.client, authRepo: authRepo);
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(router, container));
      await tester.pumpAndSettle();

      // CLIENT skip path → fires register() with the seeded draft email/pw.
      await _tap(tester, const ValueKey<String>('address_skip'));

      // (1) Banner is present with the localised UK copy.
      expect(
        find.byKey(const Key('step3-email-already-registered')),
        findsOneWidget,
        reason:
            'EmailAlreadyRegisteredFailure must render the dedicated AuthBanner '
            '(key: step3-email-already-registered) so the user can recover via '
            'the Sign In CTA.',
      );
      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(
        find.text(l10n.errEmailAlreadyRegistered),
        findsOneWidget,
        reason:
            'Banner text must use the new l10n key errEmailAlreadyRegistered '
            '(not the server-supplied "Email already registered" string).',
      );
      expect(
        find.text(l10n.errEmailAlreadyRegisteredAction),
        findsOneWidget,
        reason:
            'CTA inside the banner must use the new l10n key '
            'errEmailAlreadyRegisteredAction ("Увійти" / "Sign in").',
      );

      // (2) register() was invoked exactly once on submit — the failure path
      // must not retry behind the scenes.
      verify(
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
      ).called(1);

      // (3) Tap the Sign In CTA — navigates to /login.
      await tester.tap(
        find.byKey(const ValueKey<String>('auth_banner_action')),
      );
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.fullPath,
        equals(RouteNames.login),
        reason:
            'Tapping the Sign In CTA must navigate to RouteNames.login so the '
            'user can sign in to the existing account.',
      );
      expect(find.text('login-screen'), findsOneWidget);

      // (4) The form did NOT auto-resubmit — no additional register calls
      // beyond the single one already verified above.
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

      // (5) The verification screen was NOT reached (no false-positive
      // navigation through the success path).
      expect(find.textContaining('verification:'), findsNothing);
    },
  );

  // ── Honest post-registration card description copy ────────────────────────
  //
  // Backend ALWAYS returns 409 EMAIL_ALREADY_REGISTERED on duplicate-email
  // registrations (the disclose-duplicate-registration toggle was removed —
  // see backend commit 35e4eb8). Mobile Step 3 routes the 409 case to the
  // inline banner + Sign In CTA, so only fresh (genuinely new) email
  // registrations ever reach the verification screen. The user WILL receive
  // a code, and the copy must say so plainly.
  //
  // This test is in the step3 file because step3 is where the test framework
  // already has the wired-up provider/router. We pump the bare verification
  // copy via the canonical l10n lookup so the assertion is independent of
  // the screen widget structure (the verification screen is exercised in
  // verification_screen_test.dart; here we lock the COPY itself).
  testWidgets(
    'verificationCardDesc resolves to the honest "we sent" copy in uk '
    '(no neutral / conditional phrasing)',
    (tester) async {
      // Render a minimal MaterialApp with only AppLocalizations so we can
      // assert the resolved string for the uk locale.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Text(AppLocalizations.of(ctx).verificationCardDesc),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Positive assertion: the honest "we sent" wording is present. Only
      // fresh (non-duplicate) registrations reach this screen, so promising
      // a code is accurate.
      expect(
        find.textContaining('Ми надіслали'),
        findsOneWidget,
        reason:
            'verificationCardDesc (uk) must use the honest "Ми надіслали" '
            'phrasing — only fresh registrations reach verification (409 '
            'duplicates are caught on Step 3 via the banner + Sign In CTA).',
      );

      // Negative assertion: the old neutral conditional phrasing must not
      // leak back in. It was a stopgap for the now-removed anti-enumeration
      // silent-200 flow and reads as confusing FUD on the success path.
      expect(
        find.textContaining('Якщо ця електронна адреса ще не зареєстрована'),
        findsNothing,
        reason:
            'The neutral conditional copy must not be present — the silent-'
            '200 anti-enumeration flow it covered no longer exists.',
      );
    },
  );

  // ── Location icon tile (Phase 2.x icon standardisation) ───────────────────
  testWidgets('location-marker icon tile renders at top of Step 3 '
      '(VelvetTouch icon tile consistency — no VelvetHeader logo)', (
    tester,
  ) async {
    final container = _container(
      role: UserRole.client,
      authRepo: _MockAuthRepository(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(_makeRouter(), container));
    await tester.pump(); // addPostFrameCallback flush
    await tester.pumpAndSettle();

    // The hero tile and the LocalityCascade pins share the same asset
    // (locationMarker), so the asset alone is not a stable discriminator.
    // Anchor on the hero's own Key('register-step3-location-hero') and assert
    // the AppIcon rendered inside that 72×72 neumorphic Container — the hero
    // glyph is the larger 30 px accent marker (matching steps 1 & 2), distinct
    // from the cascade rows' 20 px pins.
    final heroTile = find.byKey(const Key('register-step3-location-hero'));
    expect(
      heroTile,
      findsOneWidget,
      reason:
          'RegisterStep3Screen must render the 72×72 neumorphic hero icon '
          'tile keyed register-step3-location-hero at the top of the screen.',
    );

    // The hero Container is a 72×72 box — the icon-tile style (not a
    // VelvetHeader logo / not a full-width banner).
    final heroBox = tester.widget<Container>(heroTile);
    expect(heroBox.constraints?.maxHeight, 72);
    expect(heroBox.constraints?.maxWidth, 72);

    // …and its single child is the locationMarker AppIcon SVG.
    final heroIcon = tester.widget<AppIcon>(
      find.descendant(of: heroTile, matching: find.byType(AppIcon)),
    );
    expect(
      heroIcon.asset,
      BeauticaAssetIcons.locationMarker,
      reason: 'Hero tile must render the locationMarker SVG glyph.',
    );
    expect(
      heroIcon.size,
      30,
      reason:
          'Hero glyph must render at the 30 px accent size (matching steps 1 '
          '& 2 hero tiles), not a full-box or shrunk glyph.',
    );

    // No VelvetHeader logo on Step 3 — the icon tile replaces it.
    expect(find.byType(VelvetHeader), findsNothing);
  });

  // ── fetchOblasts() throws during initState prefetch ───────────────────────
  //
  // Backlog: LOW — No test covers fetchOblasts() throwing during Step 3
  // initState prefetch (mobile-qa, 2026-05-24).
  //
  // When the oblast warm-up Future rejects (e.g. NetworkFailure on cold load
  // before any picker tap), the screen must not crash. The LocalityTapRow
  // stays in its initial (empty / error) state — the widget tree stays mounted.
  //
  // Mutation guard: if the prefetch addPostFrameCallback is ever wrapped with
  // a bare `await` without error handling, this test will throw an uncaught
  // exception during pumpAndSettle, failing the test as intended.
  //
  // Pump sequence note: Riverpod schedules a 200 ms retry timer after a
  // keepAlive provider throws. pumpAndSettle() alone does not advance fake
  // time past that timer — the timer stays pending at teardown and causes a
  // test failure. Pumping Duration(milliseconds: 250) advances fake time past
  // the retry tick, the timer fires harmlessly (retries → same error), and
  // pumpAndSettle then drains any resulting microtasks so the tree is clean.
  testWidgets('fetchOblasts throws NetworkFailure — screen does not crash; '
      'RegisterStep3Screen remains mounted (oblast prefetch error path)', (
    tester,
  ) async {
    final container = _container(
      role: UserRole.client,
      authRepo: _MockAuthRepository(),
      locationRepo: _FailingLocationRepository(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(_makeRouter(), container));
    // Flush the addPostFrameCallback queue so the prefetch read fires.
    await tester.pump();
    // Let the rejected Future propagate.
    await tester.pumpAndSettle();
    // Advance past Riverpod's 200 ms keepAlive-provider retry timer so it
    // fires (another failed attempt) and is removed before teardown.
    await tester.pump(const Duration(milliseconds: 250));
    // Drain microtasks from the retry attempt.
    await tester.pumpAndSettle();

    // The screen widget must still be in the tree — no crash, no blank screen.
    expect(
      find.byType(RegisterStep3Screen),
      findsOneWidget,
      reason:
          'fetchOblasts() NetworkFailure during initState prefetch must not '
          'unmount the screen. The widget tree must remain intact so the user '
          'can still interact with the form.',
    );

    // The oblast tap row must be present — it renders in its empty/error state
    // when the prefetch fails before any user interaction.
    expect(
      find.byKey(const Key('locality_row_oblast')),
      findsOneWidget,
      reason:
          'The oblast LocalityTapRow must remain in the tree after a '
          'fetchOblasts() failure so the user can retry by tapping it.',
    );
  });
}
