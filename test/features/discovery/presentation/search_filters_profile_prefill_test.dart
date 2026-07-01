// Widget tests for the saved-profile locality PREFILL on [ClientSearchScreen].
//
// Feature: when a CLIENT who has a saved location opens Пошук, the locality
// filter (oblast → city → district) is pre-filled from their profile. They can
// still change it; a client with NO saved location sees an empty filter.
//
// The prefill is a ONE-TIME, per-session seed owned by
// [SearchFiltersController.prefillFromProfileIfNeeded] (triggered by the
// screen's initState), guarded so it (a) runs at most once per session and
// (b) never clobbers a manual change. These tests pin all three behaviours:
//   a. saved location → filter (ids) + labels (names + cityHasDistricts) seeded;
//   b. no saved location → filter stays empty;
//   c. manual change after prefill survives a navigate-away-and-back (NO re-seed)
//      — the explicit anti-clobber / seamless-reload-footgun regression.
//
// All finders are key/predicate-based (locale-invariant); city/oblast NAMES are
// backend data, asserted as content only. approvedCategoriesProvider is
// overridden directly (it bypasses serviceRepositoryProvider and would otherwise
// hit the real Dio — the recorded fixture footgun).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';

// ---------------------------------------------------------------------------
// Locality taxonomy fixtures (drive the prefill's oblast → city → district
// resolution). Київ subdivides (hasDistricts: true) so the District level is
// resolvable; Львів does not.
// ---------------------------------------------------------------------------

const _kOblastId = 'oblast-kyiv';
const _kOblast = Oblast(
  id: _kOblastId,
  name: 'Київська',
  katotthCode: 'UA32000000000000000',
);

const _kCityWithDistrictsId = 'city-kyiv';
const _kCityWithDistricts = City(
  id: _kCityWithDistrictsId,
  oblastId: _kOblastId,
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: true,
);

const _kCityNoDistrictsId = 'city-lviv';
const _kCityNoDistricts = City(
  id: _kCityNoDistrictsId,
  oblastId: _kOblastId,
  name: 'Львів',
  katotthCode: 'UA46000000000026870',
  hasDistricts: false,
);

const _kDistrictId = 'dist-pechersk';
const _kDistrict = CityDistrict(
  id: _kDistrictId,
  cityId: _kCityWithDistrictsId,
  name: 'Печерський',
  katotthCode: 'UA80000000001000000',
);

const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся'),
];

// ── Users ──────────────────────────────────────────────────────────────────

// A CLIENT whose profile carries a full saved locality (Київ / Печерський).
const _userWithLocation = User(
  id: 'u-client-loc',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
  oblastId: _kOblastId,
  cityId: _kCityWithDistrictsId,
  districtId: _kDistrictId,
  oblastName: 'Київська',
  cityName: 'Київ',
  districtName: 'Печерський',
);

// A CLIENT with NO saved location at all.
const _userNoLocation = User(
  id: 'u-client-noloc',
  email: 'client2@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Клієнт',
);

// A SECOND CLIENT whose profile carries a DIFFERENT saved locality (Львів, no
// district — within the same overridden taxonomy so the cascade resolves). Used
// by the cross-session re-seed regression: after a session flip from
// [_userWithLocation] (Київ) to this user, the prefill must seed Львів and the
// prior session's Київ must NEVER persist.
const _userWithLocationLviv = User(
  id: 'u-client-lviv',
  email: 'client3@beautica.ua',
  role: UserRole.client,
  firstName: 'Оксана',
  lastName: 'Клієнт',
  oblastId: _kOblastId,
  cityId: _kCityNoDistrictsId,
  oblastName: 'Київська',
  cityName: 'Львів',
);

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

User _seededUser = _userWithLocation;

class _StubClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async {
    // Mirror production (the real ClientEditProfile.build ref.watch(authProvider)s
    // and re-fetches /users/me on a session flip): derive the profile from the
    // ACTIVE session's user so that flipping the auth session yields the NEW
    // user's saved location. The stub auth notifier carries the full location on
    // its [User], so reading session.user is equivalent to a re-fetch.
    final AuthSession? session = ref.watch(authProvider).value;
    if (session is Authenticated) return session.user;
    return _seededUser;
  }
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    final session = AuthSession.authenticated(
      user: _seededUser,
      accessToken: 'tok',
    );
    state = AsyncData<AuthSession>(session);
    return session;
  }

  /// Flips the active session to a DIFFERENT user — the login-after-logout
  /// transition within a single test. Re-emitting a fresh [Authenticated]
  /// re-runs every auth-watching provider's `build()`: the
  /// [SearchFiltersController] (re-arms its one-shot + resets to an empty filter
  /// set) and [ClientEditProfile] (re-fetches the new user's profile). This is
  /// exactly the self-clearing path the production keepAlive providers rely on.
  void flipTo(User user) {
    state = AsyncData<AuthSession>(
      AuthSession.authenticated(user: user, accessToken: 'tok-${user.id}'),
    );
  }
}

// ProviderScope / ProviderContainer overrides expect List<Override>; that name
// is not exported by this Riverpod version, so the list is built as
// List<Object> and `.cast()`-ed at the call sites (the house pattern — see
// test/helpers/pump_app.dart).
List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
  secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
  serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
  clientEditProfileProvider.overrideWith(_StubClientEditProfile.new),
  // approvedCategoriesProvider bypasses serviceRepositoryProvider — override it
  // directly so the category rail never reaches the real Dio (fixture footgun).
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[..._categories],
  ),
  // Taxonomy the prefill resolves the saved ids against.
  oblastListProvider.overrideWith((ref) async => const <Oblast>[_kOblast]),
  cityListProvider(_kOblastId).overrideWith(
    (ref) async => const <City>[_kCityWithDistricts, _kCityNoDistricts],
  ),
  districtListProvider(
    _kCityWithDistrictsId,
  ).overrideWith((ref) async => const <CityDistrict>[_kDistrict]),
];

Widget _app() => const MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale('uk'),
  home: ClientSearchScreen(),
);

void _sizeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

SearchFilters _filters(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFiltersControllerProvider);

SearchFilterLabels _labels(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFilterLabelsControllerProvider);

void main() {
  setUp(() => _seededUser = _userWithLocation);

  group('ClientSearchScreen — saved-location prefill', () {
    testWidgets(
      'a CLIENT with a saved location → the locality filter is pre-filled '
      '(ids + labels incl. cityHasDistricts)',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        _seededUser = _userWithLocation;

        await tester.pumpWidget(
          ProviderScope(overrides: _overrides().cast(), child: _app()),
        );
        await tester.pumpAndSettle();

        // Wire-facing ids seeded from the profile.
        final SearchFilters f = _filters(tester);
        expect(f.oblastId, _kOblastId);
        expect(f.cityId, _kCityWithDistrictsId);
        expect(f.districtId, _kDistrictId);

        // Display labels seeded — cityHasDistricts resolved from the taxonomy
        // (not hardcoded), so the District row gates open correctly.
        final SearchFilterLabels labels = _labels(tester);
        expect(labels.oblastName, 'Київська');
        expect(labels.cityName, 'Київ');
        expect(labels.cityHasDistricts, isTrue);
        expect(labels.districtName, 'Печерський');

        // The city row renders the seeded name (content assertion on the keyed
        // value Text).
        final Text cityText = tester.widget<Text>(
          find.byKey(const Key('search_city_value')),
        );
        expect(cityText.data, 'Київ');
      },
    );

    testWidgets('a CLIENT with NO saved location → the filter stays empty', (
      tester,
    ) async {
      installOverflowGuard();
      _sizeView(tester);
      _seededUser = _userNoLocation;

      await tester.pumpWidget(
        ProviderScope(overrides: _overrides().cast(), child: _app()),
      );
      await tester.pumpAndSettle();

      final SearchFilters f = _filters(tester);
      expect(f.oblastId, isNull);
      expect(f.cityId, isNull);
      expect(f.districtId, isNull);

      final SearchFilterLabels labels = _labels(tester);
      expect(labels.oblastName, isNull);
      expect(labels.cityName, isNull);
      expect(labels.districtName, isNull);

      // The city row shows its placeholder, not a seeded name.
      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('uk'),
      );
      final Text cityText = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityText.data, l10n.searchCityPlaceholder);
    });

    testWidgets('a manual change after prefill SURVIVES a navigate-away-and-back '
        '(same session → NO re-seed)', (tester) async {
      installOverflowGuard();
      _sizeView(tester);
      _seededUser = _userWithLocation;

      // A single container survives the away-and-back so the keepAlive
      // controllers (and the one-shot guard) persist — exactly as a real
      // in-session navigation would.
      final ProviderContainer container = ProviderContainer(
        overrides: _overrides().cast(),
      );
      addTearDown(container.dispose);

      // 1. Open Пошук → prefill seeds Київ.
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _app()),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityWithDistrictsId,
      );

      // 2. The user manually switches to Львів (a different city in the same
      //    region), mirroring a real pick (filter + labels).
      container.read(searchFiltersControllerProvider.notifier)
        ..selectOblast(oblastId: _kOblastId)
        ..selectCity(cityId: _kCityNoDistrictsId);
      container.read(searchFilterLabelsControllerProvider.notifier)
        ..setOblastName('Київська')
        ..setCityName('Львів')
        ..setCityHasDistricts(false)
        ..setDistrictName(null);
      await tester.pump();
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityNoDistrictsId,
      );

      // 3. Navigate AWAY (unmounts the screen) ...
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox(key: Key('away'))),
        ),
      );
      await tester.pumpAndSettle();

      // 4. ... and BACK (a fresh ClientSearchScreen → initState re-fires the
      //    prefill trigger).
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _app()),
      );
      await tester.pumpAndSettle();

      // The manual choice is intact — the prefill did NOT re-seed back to the
      // profile's Київ (this is the anti-clobber / seamless-reload regression).
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        _kCityNoDistrictsId,
        reason:
            'a re-entry in the same session must not overwrite a manual '
            'locality change with the saved-profile seed',
      );
      expect(
        container.read(searchFilterLabelsControllerProvider).cityName,
        'Львів',
      );
    });

    testWidgets(
      'a session FLIP (user A → user B) re-arms the one-shot and re-seeds with '
      "B's saved location — A's locality NEVER leaks into B's session "
      '(cross-session-leak guard)',
      (tester) async {
        installOverflowGuard();
        _sizeView(tester);
        // User A signs in with the Київ profile.
        _seededUser = _userWithLocation;

        // One container survives the whole flow (the keepAlive controllers + the
        // session flip live in it) — exactly as the real app's single root
        // ProviderScope does across a logout→login within one process.
        final ProviderContainer container = ProviderContainer(
          overrides: _overrides().cast(),
        );
        addTearDown(container.dispose);

        // 1. User A opens Пошук → prefill seeds Київ (the city WITH districts).
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          _kCityWithDistrictsId,
          reason: "user A's saved Київ must seed on first open",
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          'Київ',
        );

        // 2. The session FLIPS to user B (saved location Львів). Re-emitting a
        //    fresh Authenticated re-runs SearchFiltersController.build (watches
        //    authProvider) → it resets to an EMPTY filter set and re-arms the
        //    one-shot. This is the moment A's locality must be shed.
        final _StubAuthNotifier auth =
            container.read(authProvider.notifier) as _StubAuthNotifier;
        auth.flipTo(_userWithLocationLviv);
        await tester.pump();

        // Immediately after the flip — BEFORE any re-seed — A's Київ is already
        // gone: the auth-watched build() cleared the keepAlive filter + labels.
        // This is the core leak assertion: a stale per-user filter cannot
        // survive the session boundary.
        expect(
          container.read(searchFiltersControllerProvider).cityId,
          isNull,
          reason:
              "the session flip must clear user A's seeded locality before B "
              'is seeded (no cross-session leak)',
        );
        expect(
          container.read(searchFilterLabelsControllerProvider).cityName,
          isNull,
        );

        // 3. User B navigates AWAY (unmount) ...
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SizedBox(key: Key('away'))),
          ),
        );
        await tester.pumpAndSettle();

        // 4. ... and BACK into Пошук (a fresh ClientSearchScreen → initState
        //    re-fires the prefill against the NEW session).
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: _app()),
        );
        await tester.pumpAndSettle();

        // 5. The prefill re-armed and seeded B's Львів — NOT A's Київ.
        final SearchFilters f = container.read(searchFiltersControllerProvider);
        expect(
          f.cityId,
          _kCityNoDistrictsId,
          reason: "user B's saved Львів must seed in the new session",
        );
        expect(
          f.cityId,
          isNot(_kCityWithDistrictsId),
          reason: "user A's Київ must never appear in user B's session",
        );
        expect(f.districtId, isNull, reason: 'Львів has no district');

        final SearchFilterLabels labels = container.read(
          searchFilterLabelsControllerProvider,
        );
        expect(labels.cityName, 'Львів');
        expect(
          labels.cityHasDistricts,
          isFalse,
          reason: 'the District row gates closed for the no-districts Львів',
        );

        // And the rendered city row shows B's city — never A's.
        final Text cityText = tester.widget<Text>(
          find.byKey(const Key('search_city_value')),
        );
        expect(cityText.data, 'Львів');
      },
    );
  });
}
