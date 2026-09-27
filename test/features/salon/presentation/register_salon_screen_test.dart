// Phase 21.3 — Widget tests for RegisterSalonScreen + RegisterSalon notifier.
//
// Covers:
//   1. Field validators — an empty submit blocks, never reaches
//      SalonRepository.create, and surfaces inline errors on name/locality/
//      street/building/phone.
//   2. Contacts prefill — phone/Instagram seed from the owner's PRIMARY
//      salon via mySalonsProvider, with the muted "Підставлено..." hint.
//   3. Submit success — a valid form sends the correct SalonCreateDto
//      (including the ADDITIVE instagramUrl field), shows the success snack,
//      and pops back to the hub.
//   4. Submit error — a repository failure shows an error snack WITHOUT
//      popping.
//   5. mySalonsProvider invalidation — a successful submit() invalidates the
//      keepAlive hub list so it refetches on its next read (mirrors
//      `salon_management_profile_notifier_test.dart`'s proven pattern).
//   6. SALON_OWNER-only gate — the PRODUCTION router admits SALON_OWNER and
//      bounces every other authenticated role away from /salons/register.
//
// Strategy mirrors `salon_edit_forms_test.dart`: a real GoRouter (via
// `pumpRoutedApp`) with `salonRepositoryProvider` overridden by the shared
// `FakeSalonRepository` fake, and `locationRepositoryProvider` stubbed with a
// small fixed fake.
//
// Phase 346 — the «Область» → «Місто» → «Район» LocalityCascade is GONE,
// replaced by [SettlementLocalityField] (one autocomplete + a conditional
// district row). Settlement selection is driven through the REAL bottom
// sheet (tap the closed field → type ≥3 chars → let the debounce elapse →
// tap the row) via `_selectSettlement`, backed by a `locationRepositoryProvider`
// fake — there is no `locality_row_oblast`/`locality_row_city` to tap any
// more. See `settlement_select_field_test.dart`'s header for why the
// explicit `pump(kSettlementSearchDebounce)` is load-bearing.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_tap_row.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/register_salon_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/register_salon_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/fakes/fake_service_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _stubOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

/// A leaf settlement — no urban districts, so [SettlementLocalityField]
/// renders no district row for it.
const _settlement = Settlement(
  id: 'settlement-01',
  name: 'Київ',
  oblastName: 'Київ',
);

/// A settlement that subdivides — used by the district-required and
/// district-clearing tests.
const _settlementWithDistricts = Settlement(
  id: 'settlement-02-districts',
  name: 'Дніпро',
  oblastName: 'Дніпропетровська',
);

const _district = CityDistrict(
  id: 'district-01',
  cityId: 'settlement-02-districts',
  name: 'Соборний',
  katotthCode: 'UA12-020-0136',
);

/// Fixed fake backing `locationRepositoryProvider` — resolves the settlement
/// search to a small fixed list (ignoring the query text; see
/// `settlement_select_field_test.dart` for dedicated query-shape coverage)
/// and resolves districts per settlement id.
class _FakeLocationRepository implements LocationRepository {
  const _FakeLocationRepository();

  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) async => const <Settlement>[_settlement, _settlementWithDistricts];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      cityId == _settlementWithDistricts.id
      ? const <CityDistrict>[_district]
      : const <CityDistrict>[];

  @override
  Future<List<Oblast>> fetchOblasts() => throw UnimplementedError();

  @override
  Future<List<City>> fetchCities(String oblastId) => throw UnimplementedError();
}

const _locationRepo = _FakeLocationRepository();

/// [_FakeLocationRepository] whose district lookup holds on [gate] — keeps it
/// IN FLIGHT so a test can submit against it (perf N1).
class _GatedLocationRepository extends _FakeLocationRepository {
  _GatedLocationRepository(this.gate);

  final Completer<void> gate;

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async {
    await gate.future;
    return super.fetchDistricts(cityId);
  }
}

/// The owner's existing PRIMARY salon — its phone/Instagram seed
/// RegisterSalonScreen's own contact fields.
const _primarySalon = Salon(
  id: 'salon-1',
  name: 'Салон «Вельвет»',
  isPrimary: true,
  phone: '+380501234567',
  instagramUrl: 'velvet_salon',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubOwner, accessToken: 'tok');
}

/// [MySalons] stub serving a fixed list — mirrors `my_salons_screen_test
/// .dart`'s own `_StubMySalons`.
class _StubMySalons extends MySalons {
  _StubMySalons(this._builder);

  final Future<List<Salon>> Function() _builder;

  @override
  Future<List<Salon>> build() => _builder();
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.mySalons,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.mySalons,
      builder: (context, state) => const Scaffold(key: Key('hub-marker')),
    ),
    GoRoute(
      path: RouteNames.registerSalon,
      builder: (context, state) => const RegisterSalonScreen(),
    ),
  ],
);

List<Object> _overrides(
  FakeSalonRepository repo, {
  List<Salon> mySalons = const <Salon>[_primarySalon],
  LocationRepository locationRepo = _locationRepo,
}) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
  mySalonsProvider.overrideWith(() => _StubMySalons(() async => mySalons)),
  locationRepositoryProvider.overrideWithValue(locationRepo),
];

/// Selects [settlement] through the REAL search sheet: open → type a query
/// long enough to clear the "type more" hint → let the debounce elapse →
/// tap the row. There is no `LocalityCascade.onCity`/`onOblast` callback to
/// invoke directly any more (phase 346).
Future<void> _selectSettlement(
  WidgetTester tester,
  Settlement settlement,
) async {
  await tester.tap(find.byKey(const Key('settlement_select_field')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('select-menu-search')),
    settlement.name,
  );
  await tester.pump(kSettlementSearchDebounce);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settlement_option_${settlement.id}')));
  await tester.pumpAndSettle();
}

/// Fills every REQUIRED field with a valid value (name, settlement leaf of no
/// districts, street, building). Phone/Instagram are left as whatever the
/// screen already prefilled — callers that need bare/empty contacts should
/// pass an owner with no salons via [_overrides].
Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('salon_name')), 'Салон Марії');
  await tester.pump();

  await _selectSettlement(tester, _settlement);

  await tester.enterText(
    find.byKey(const Key('salon_street')),
    'вул. Хрещатик',
  );
  await tester.pump();
  await tester.enterText(find.byKey(const Key('salon_building')), '5');
  await tester.pump();
}

void main() {
  testWidgets('N1 — a double tap on create while the district lookup is still '
      'in flight creates ONE salon', (tester) async {
    final Completer<void> gate = Completer<void>();
    final repo = FakeSalonRepository(salon: _primarySalon);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpRoutedApp(
      router,
      overrides: _overrides(repo, locationRepo: _GatedLocationRepository(gate)),
    );
    await tester.pumpAndSettle();

    unawaited(router.push(RouteNames.registerSalon));
    await tester.pumpAndSettle();
    await _fillValidForm(tester);

    await tester.tap(find.byKey(const Key('create_salon')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('create_salon')));
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(repo.createRequests, hasLength(1));
  });

  group('field validators', () {
    testWidgets(
      'an empty submit blocks, never reaches create(), and surfaces inline '
      'errors on name/locality/street/building/phone',
      (tester) async {
        final repo = FakeSalonRepository(salon: _primarySalon);
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides(repo, mySalons: const <Salon>[]),
        );
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.registerSalon));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('create_salon')));
        await tester.pumpAndSettle();

        expect(repo.createRequests, isEmpty);

        // VelvetField/SearchableSelectField surface errors via a dedicated
        // Row, not InputDecoration.errorText — assert through the visible
        // text.
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.errSalonNameRequired), findsOneWidget);
        expect(find.text(l10n.errStreetRequired), findsOneWidget);
        expect(find.text(l10n.errBuildingRequired), findsOneWidget);
        expect(find.text(l10n.errPhoneRequired), findsOneWidget);

        // `errSettlementRequired` and `settlementPlaceholder` are the SAME
        // Ukrainian string («Оберіть населений пункт») — a plain
        // `find.text` would match both the closed field's placeholder and
        // the error row and can't tell them apart, so the widget's own
        // `errorText` is asserted directly instead (mirrors the pre-346
        // `LocalityTapRow.errorText` check this replaces).
        expect(
          tester
              .widget<SettlementSelectField>(find.byType(SettlementSelectField))
              .errorText,
          l10n.errSettlementRequired,
          reason: 'locality is required from scratch, like register step 3',
        );

        // Phase 346 (Qase case 3 step 5) — the retired «Область»/«Місто»
        // rows must never reappear on this screen.
        expect(find.byKey(const Key('locality_row_oblast')), findsNothing);
        expect(find.byKey(const Key('locality_row_city')), findsNothing);
      },
    );
  });

  group('contacts prefill', () {
    testWidgets('phone/Instagram seed from the PRIMARY salon and show the '
        "«Підставлено...» hint", (tester) async {
      final repo = FakeSalonRepository(salon: _primarySalon);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.registerSalon));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('salon_phone')))
            .controller!
            .text,
        _primarySalon.phone,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('salon_instagram')))
            .controller!
            .text,
        _primarySalon.instagramUrl,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(find.text(l10n.registerSalonPrefilledHint), findsOneWidget);
    });

    testWidgets(
      'an owner with no salons yet leaves contacts empty and shows no hint',
      (tester) async {
        final repo = FakeSalonRepository(salon: _primarySalon);
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides(repo, mySalons: const <Salon>[]),
        );
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.registerSalon));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byKey(const Key('salon_phone')))
              .controller!
              .text,
          isEmpty,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.registerSalonPrefilledHint), findsNothing);
      },
    );
  });

  group('submit', () {
    testWidgets(
      'a valid form sends the correct SalonCreateDto, shows the success '
      'snack, and pops back to the hub',
      (tester) async {
        final repo = FakeSalonRepository(salon: _primarySalon);
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.registerSalon));
        await tester.pumpAndSettle();

        await _fillValidForm(tester);

        await tester.tap(find.byKey(const Key('create_salon')));
        await tester.pump();
        await pumpVelvetSnackIn(tester);

        expect(repo.createRequests, hasLength(1));
        final SalonCreateDto sent = repo.createRequests.single;
        expect(sent.name, 'Салон Марії');
        expect(sent.cityId, _settlement.id);
        expect(sent.districtId, isNull);
        expect(sent.street, 'вул. Хрещатик');
        expect(sent.buildingNo, '5');
        // Prefilled from the primary salon, unmodified by this flow.
        expect(sent.phone, _primarySalon.phone);
        expect(sent.instagramUrl, _primarySalon.instagramUrl);

        // Popped back to the hub.
        expect(find.byKey(const Key('hub-marker')), findsOneWidget);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'picking a district-requiring city with no district selected blocks '
      'submit',
      (tester) async {
        final repo = FakeSalonRepository(salon: _primarySalon);
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(router, overrides: _overrides(repo));
        await tester.pumpAndSettle();

        unawaited(router.push(RouteNames.registerSalon));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('salon_name')),
          'Салон Марії',
        );
        await _selectSettlement(tester, _settlementWithDistricts);
        // Deliberately do NOT pick a district.
        await tester.enterText(
          find.byKey(const Key('salon_street')),
          'вул. Хрещатик',
        );
        await tester.enterText(find.byKey(const Key('salon_building')), '5');

        await tester.tap(find.byKey(const Key('create_salon')));
        await tester.pumpAndSettle();

        expect(repo.createRequests, isEmpty);
        expect(find.byKey(const Key('hub-marker')), findsNothing);
      },
    );

    testWidgets('a repository failure shows an error snack WITHOUT popping', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _primarySalon)
        ..createError = const ServerFailure(statusCode: 500);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.registerSalon));
      await tester.pumpAndSettle();

      await _fillValidForm(tester);

      await tester.tap(find.byKey(const Key('create_salon')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expect(repo.createRequests, hasLength(1));
      // Still on the form — the pop never happened.
      expect(find.byKey(const Key('salon_name')), findsOneWidget);
      expect(find.byKey(const Key('hub-marker')), findsNothing);
      await pumpPastVelvetSnack(tester);
    });
  });

  group('district clears on settlement change', () {
    testWidgets('picking a new settlement always clears a previously selected '
        'district', (tester) async {
      final repo = FakeSalonRepository(salon: _primarySalon);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(router, overrides: _overrides(repo));
      await tester.pumpAndSettle();

      unawaited(router.push(RouteNames.registerSalon));
      await tester.pumpAndSettle();

      // Pick the subdividing settlement — the district row appears.
      await _selectSettlement(tester, _settlementWithDistricts);
      expect(find.byKey(const Key('locality_row_district')), findsOneWidget);

      await tester.tap(find.byKey(const Key('locality_row_district')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey<String>('locality_picker_tile_${_district.id}')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<LocalityTapRow>(
              find.byKey(const Key('locality_row_district')),
            )
            .value,
        _district.name,
      );

      // Now pick a DIFFERENT, leaf settlement — the district row must
      // vanish (a `CityDistrict` belongs to exactly one settlement, so
      // carrying the old selection across would submit a district that is
      // not a child of the newly-submitted city).
      await _selectSettlement(tester, _settlement);

      expect(find.byKey(const Key('locality_row_district')), findsNothing);
    });
  });

  group('mySalonsProvider invalidation', () {
    // Mutable box so a build() call count survives mySalonsProvider being
    // recreated by ref.invalidate — mirrors
    // `salon_management_profile_notifier_test.dart`'s proven `_CallCounter`
    // + `_CountingMySalons` pattern exactly.
    test('a successful submit() invalidates mySalonsProvider so the hub '
        'refetches on its next read', () async {
      final counter = _CallCounter();
      final repo = FakeSalonRepository(salon: _primarySalon);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_StubAuthNotifier.new),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          salonRepositoryProvider.overrideWithValue(repo),
          mySalonsProvider.overrideWith(() => _CountingMySalons(counter)),
        ],
      );
      addTearDown(container.dispose);

      // A prior hub visit seeds the keepAlive cache BEFORE the create.
      await container.read(mySalonsProvider.future);
      expect(counter.value, 1);

      final failure = await container
          .read(registerSalonProvider.notifier)
          .submit(
            name: 'Салон Марії',
            cityId: _settlement.id,
            street: 'вул. Хрещатик',
            buildingNo: '5',
          );
      expect(failure, isNull);
      expect(repo.createRequests, hasLength(1));

      // Invalidation alone does not eagerly rebuild a keepAlive provider —
      // it rebuilds on its NEXT read, exactly like the hub screen's own
      // `ref.watch(mySalonsProvider)` would on remount.
      await container.read(mySalonsProvider.future);
      expect(
        counter.value,
        2,
        reason:
            'submit() must invalidate mySalonsProvider — without it the '
            'hub renders the pre-create cached list for the rest of the '
            'session',
      );
    });
  });

  group('SALON_OWNER-only gate', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    testWidgets('a SALON_OWNER is admitted to /salons/register', (
      tester,
    ) async {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(_StubAuthNotifier.new),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          mySalonsProvider.overrideWith(
            () => _StubMySalons(() async => const <Salon>[_primarySalon]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk', 'UA'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.go(RouteNames.registerSalon);
      await tester.pumpAndSettle();

      expect(find.byType(RegisterSalonScreen), findsOneWidget);
    });

    testWidgets(
      'a non-owner authenticated role is bounced to its own landing',
      (tester) async {
        const nonOwner = User(
          id: 'staff-1',
          email: 'staff@beautica.ua',
          role: UserRole.salonMaster,
          firstName: 'Іван',
          lastName: 'Майстров',
        );
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            authProvider.overrideWith(() => _FixedRoleAuthNotifier(nonOwner)),
            authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
            secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
            // roleHomePath(salonMaster) now resolves to a real landing
            // (RouteNames.salonMasterProfile -> SalonMasterProfileScreen,
            // fixing the "blank home" bug) instead of falling through the
            // old wildcard arm onto the bare `/` placeholder. Settle its two
            // data sources synchronously so the bounce doesn't leak a Dio
            // request/Timer — same overrides
            // `salon_manage_route_guard_test.dart` uses for the identical
            // SALON_MASTER bounce case.
            masterProfileProvider.overrideWith(
              _SettledMasterProfileNotifier.new,
            ),
            publicServiceRepositoryProvider.overrideWith(
              (_) => FakeServiceRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(appRouterProvider);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk', 'UA'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        router.go(RouteNames.registerSalon);
        await tester.pumpAndSettle();

        expect(find.byType(RegisterSalonScreen), findsNothing);
        // roleHomePath(salonMaster) is RouteNames.salonMasterProfile
        // (`/staff/profile`, SalonMasterProfileScreen) — the role's own
        // read-only self-view landing. `roleHomePath`'s switch is exhaustive
        // now (the old `_ =>` wildcard that dumped every non-mapped role on
        // the bare `/` placeholder is gone), so SALON_MASTER was chosen
        // deliberately: it is the role this gate actually bounces in
        // production, and asserting its REAL landing is a stronger check
        // than the old blank-page assertion ever was.
        expect(
          // router-location-ok: only router.go(...) is used in this group.
          router.routerDelegate.currentConfiguration.uri.toString(),
          equals(RouteNames.salonMasterProfile),
        );
      },
    );
  });
}

/// Mutable box so a `build()` call count survives `mySalonsProvider` being
/// recreated by `ref.invalidate` — mirrors
/// `salon_management_profile_notifier_test.dart`'s own `_CallCounter`.
class _CallCounter {
  int value = 0;
}

/// [MySalons] stub that increments [counter] on every `build()`.
class _CountingMySalons extends MySalons {
  _CountingMySalons(this.counter);

  final _CallCounter counter;

  @override
  Future<List<Salon>> build() async {
    counter.value++;
    return const <Salon>[_primarySalon];
  }
}

/// [AuthNotifier] stub pinned to a specific role — used by the gate test's
/// non-owner bounce case.
class _FixedRoleAuthNotifier extends AuthNotifier {
  _FixedRoleAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'tok');
}

/// [MasterProfile] stub that resolves immediately so a SALON_MASTER bounced
/// to `RouteNames.salonMasterProfile` mounts `SalonMasterProfileScreen`
/// without the real Dio stack firing — mirrors
/// `salon_manage_route_guard_test.dart`'s `_SettledMasterProfileNotifier`
/// (same leaked-timer avoidance).
class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'sm-register-gate-1',
    firstName: 'Salon',
    lastName: 'Master',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.salonMaster,
  );
}
