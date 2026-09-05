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
// `FakeSalonRepository` fake, `oblastListProvider`/`cityListProvider`/
// `districtListProvider` stubbed with small fixtures.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/locality_tap_row.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
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

const _oblast = Oblast(id: 'oblast-01', name: 'Київська', katotthCode: 'UA1');
const _city = City(
  id: 'city-01',
  oblastId: 'oblast-01',
  name: 'Київ',
  katotthCode: 'UA1-1',
  hasDistricts: false,
);
const _cityWithDistricts = City(
  id: 'city-02-districts',
  oblastId: 'oblast-01',
  name: 'Дніпро',
  katotthCode: 'UA1-2',
  hasDistricts: true,
);
const _district = CityDistrict(
  id: 'district-01',
  cityId: 'city-02-districts',
  name: 'Соборний',
  katotthCode: 'UA1-2-1',
);

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
}) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
  mySalonsProvider.overrideWith(() => _StubMySalons(() async => mySalons)),
  oblastListProvider.overrideWith((ref) async => const <Oblast>[_oblast]),
  cityListProvider(
    'oblast-01',
  ).overrideWith((ref) async => const <City>[_city, _cityWithDistricts]),
  districtListProvider(
    _cityWithDistricts.id,
  ).overrideWith((ref) async => const <CityDistrict>[_district]),
];

/// Fills every REQUIRED field with a valid value (name, oblast → city
/// leaf-of-no-districts, street, building). Phone/Instagram are left as
/// whatever the screen already prefilled — callers that need bare/empty
/// contacts should pass an owner with no salons via [_overrides].
Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('salon_name')), 'Салон Марії');
  await tester.pump();

  await tester.tap(find.byKey(const Key('locality_row_oblast')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey<String>('locality_picker_tile_${_oblast.id}')),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('locality_row_city')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey<String>('locality_picker_tile_${_city.id}')),
  );
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('salon_street')),
    'вул. Хрещатик',
  );
  await tester.pump();
  await tester.enterText(find.byKey(const Key('salon_building')), '5');
  await tester.pump();
}

void main() {
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

        // VelvetField surfaces errors via a dedicated Row, not
        // InputDecoration.errorText — assert through the visible text.
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.errSalonNameRequired), findsOneWidget);
        expect(find.text(l10n.errStreetRequired), findsOneWidget);
        expect(find.text(l10n.errBuildingRequired), findsOneWidget);
        expect(find.text(l10n.errPhoneRequired), findsOneWidget);

        final LocalityTapRow oblastRow = tester.widget<LocalityTapRow>(
          find.byKey(const Key('locality_row_oblast')),
        );
        expect(
          oblastRow.errorText,
          isNotNull,
          reason: 'locality is required from scratch, like register step 3',
        );
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
        expect(sent.cityId, _city.id);
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
        await tester.tap(find.byKey(const Key('locality_row_oblast')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey<String>('locality_picker_tile_${_oblast.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('locality_row_city')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey<String>('locality_picker_tile_${_cityWithDistricts.id}'),
          ),
        );
        await tester.pumpAndSettle();
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
            cityId: _city.id,
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
          oblastListProvider.overrideWith((ref) async => const <Oblast>[]),
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
