// Location-fix — clientProfile provider unit tests.
//
// The home hub derives [ClientProfileSummary] from the authenticated session's
// [User] (hydrated via repo.me() → UserMapper.fromProfileDto, which now carries
// cityName / phoneNumber). These tests pin the city/phone wiring:
//   • cityName="Київ" / phoneNumber set ⇒ summary.city/phone reflect them
//     (fast path — no taxonomy fetch).
//   • cityName empty but cityId+oblastId set ⇒ summary.city resolves from the
//     location taxonomy (cityListProvider) by matching the city id.
//   • cityName empty AND no cityId/oblastId ⇒ summary.city == '' so the profile
//     card renders its placeholder path.
//
// `clientProfile` now transitively wires `cityListProvider` (a family that
// fetches via [LocationRepository]) to resolve the display name when the
// denormalized `User.cityName` is absent. The harness therefore overrides
// [locationRepositoryProvider] with a fake so the dependency graph resolves in
// test scope — mirroring the override style used across the location tests.
// Without it the still-loading `cityListProvider` leaf would dispose the whole
// graph mid-load (Riverpod 3.x: "disposed during loading state").
//
// Strategy: override authProvider with a fixed authenticated session and read
// clientProfileProvider.future from a ProviderContainer (no widget tree). A
// keep-open `container.listen(...)` subscription holds the provider alive until
// its future settles so teardown never races the in-flight load.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Auth stub
// ---------------------------------------------------------------------------

/// Stubs [authProvider] to a settled, authenticated session carrying [user].
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async {
    final session = AuthSession.authenticated(
      user: _user,
      accessToken: 'token',
    );
    state = AsyncData(session);
    return session;
  }
}

// ---------------------------------------------------------------------------
// Location stub
// ---------------------------------------------------------------------------

/// Fake [LocationRepository] returning a fixed city list for every oblast and a
/// fixed district list for every city.
///
/// `clientProfile._resolveCityName` reaches [fetchCities];
/// `_resolveDistrictName` reaches [fetchDistricts] (only when the user has a
/// `districtId` but no denormalized `districtName`). [fetchDistrictsCalls]
/// records how many times the district route was hit so the denormalized
/// fast-path test can assert it was NOT fetched. The oblast method throws if
/// hit so a stray dependency surfaces loudly instead of silently returning
/// empty data.
class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository(this._cities, {List<CityDistrict>? districts})
    : _districts = districts ?? const <CityDistrict>[];

  final List<City> _cities;
  final List<CityDistrict> _districts;

  /// Number of times [fetchDistricts] was invoked. Used to assert the
  /// denormalized `User.districtName` fast-path skips the taxonomy fetch.
  int fetchDistrictsCalls = 0;

  @override
  Future<List<City>> fetchCities(String oblastId) async => _cities;

  @override
  Future<List<Oblast>> fetchOblasts() =>
      throw UnimplementedError('fetchOblasts not used in this test');

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async {
    fetchDistrictsCalls++;
    return _districts;
  }
}

/// Pairs the built [ProviderContainer] with the [_FakeLocationRepository] backing
/// it so tests can assert on `fetchDistrictsCalls` (the denormalized fast-path).
typedef _Harness = ({ProviderContainer container, _FakeLocationRepository repo});

/// Builds a [ProviderContainer] wired with [user] and a fake location
/// repository serving [cities] (and optionally [districts]).
///
/// Holds [clientProfileProvider] alive with a no-op [ProviderContainer.listen]
/// subscription so the container is not torn down while the provider's future
/// is still loading.
_Harness _harnessForUser(
  User user, {
  List<City> cities = const <City>[],
  List<CityDistrict> districts = const <CityDistrict>[],
}) {
  final repo = _FakeLocationRepository(cities, districts: districts);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(user)),
      locationRepositoryProvider.overrideWith((_) => repo),
    ],
  );
  addTearDown(container.dispose);
  // Keep the provider mounted until its future settles so the container's
  // teardown never disposes it mid-load.
  final sub = container.listen(
    clientProfileProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(sub.close);
  return (container: container, repo: repo);
}

/// Convenience wrapper that returns just the container for the existing
/// city-only tests that do not assert on district fetch counts.
ProviderContainer _containerForUser(
  User user, {
  List<City> cities = const <City>[],
}) => _harnessForUser(user, cities: cities).container;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _userWithCity = User(
  id: 'usr-1',
  email: 'olena@beautica.test',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Тест',
  cityName: 'Київ',
  phoneNumber: '+380 97 000 00 00',
);

/// cityName empty but cityId + oblastId set — exercises the taxonomy fallback.
const _userResolvableCity = User(
  id: 'usr-3',
  email: 'resolve@beautica.test',
  role: UserRole.client,
  firstName: 'Ірина',
  lastName: 'Львів',
  cityId: 'city-kyiv',
  oblastId: 'oblast-kyiv',
  // cityName intentionally null — must be resolved from cityListProvider.
);

/// cityName empty, cityId + oblastId set, but the taxonomy returns no [City]
/// whose id matches — exercises the `_resolveCityName` loop-miss / catch branch.
const _userUnresolvableCity = User(
  id: 'usr-4',
  email: 'unresolved@beautica.test',
  role: UserRole.client,
  firstName: 'Невідоме',
  lastName: 'Місто',
  cityId: 'city-missing',
  oblastId: 'oblast-kyiv',
  // cityName intentionally null — and the fake city list never contains
  // `city-missing`, so resolution must fall back to ''.
);

const _userNoCity = User(
  id: 'usr-2',
  email: 'noloc@beautica.test',
  role: UserRole.client,
  firstName: 'Без',
  lastName: 'Міста',
  // cityName / cityId / oblastId / phoneNumber intentionally null — CLIENT
  // location is optional, so the placeholder path applies.
);

const _kyivCity = City(
  id: 'city-kyiv',
  oblastId: 'oblast-kyiv',
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: true,
);

// ── District-display fixtures ───────────────────────────────────────────────
//
// The CLIENT profile locality now shows "<city>, <district>" when districtId is
// set and resolvable. Lviv + Sykhivskyi raion exercise the combined label.

const _lvivCity = City(
  id: 'city-lviv',
  oblastId: 'oblast-lviv',
  name: 'Львів',
  katotthCode: 'UA46000000000026686',
  hasDistricts: true,
);

const _sykhivDistrict = CityDistrict(
  id: 'district-sykhiv',
  cityId: 'city-lviv',
  name: 'Сихівський район',
  katotthCode: 'UA46060370000000000',
);

/// cityName empty (cityId resolves "Львів") + districtId set and present in the
/// taxonomy → combined "Львів, Сихівський район".
const _userLvivWithDistrict = User(
  id: 'usr-d1',
  email: 'lviv-district@beautica.test',
  role: UserRole.client,
  firstName: 'Софія',
  lastName: 'Сихів',
  cityId: 'city-lviv',
  oblastId: 'oblast-lviv',
  districtId: 'district-sykhiv',
  // cityName + districtName intentionally null → both resolved from taxonomy.
);

/// cityId resolves "Львів" but districtId is null → bare "Львів".
const _userLvivNoDistrict = User(
  id: 'usr-d2',
  email: 'lviv-nodistrict@beautica.test',
  role: UserRole.client,
  firstName: 'Софія',
  lastName: 'Без',
  cityId: 'city-lviv',
  oblastId: 'oblast-lviv',
  // districtId intentionally null.
);

/// cityId resolves "Львів" + districtId set but ABSENT from the taxonomy →
/// graceful fallback to bare "Львів" (no throw).
const _userLvivUnresolvableDistrict = User(
  id: 'usr-d3',
  email: 'lviv-baddistrict@beautica.test',
  role: UserRole.client,
  firstName: 'Софія',
  lastName: 'Невідомий',
  cityId: 'city-lviv',
  oblastId: 'oblast-lviv',
  districtId: 'district-missing',
  // districtName null → taxonomy lookup runs but finds no match.
);

/// Denormalized districtName present (fast path) → used WITHOUT a
/// districtListProvider fetch.
const _userLvivDenormDistrict = User(
  id: 'usr-d4',
  email: 'lviv-denorm@beautica.test',
  role: UserRole.client,
  firstName: 'Софія',
  lastName: 'Денорм',
  cityName: 'Львів',
  districtId: 'district-sykhiv',
  districtName: 'Сихівський район',
  // cityId/oblastId omitted: city resolves via the cityName fast path, and the
  // districtName fast path means the district route must never be hit.
);

void main() {
  group('clientProfile provider', () {
    test(
      'cityName="Київ" ⇒ summary.city == "Київ" and phone is wired',
      () async {
        // The taxonomy override is required for the dependency graph to mount
        // even though this fast path never awaits cityListProvider.
        final container = _containerForUser(_userWithCity);

        final summary = await container.read(clientProfileProvider.future);

        expect(summary.city, 'Київ');
        expect(summary.phone, '+380 97 000 00 00');
        expect(summary.firstName, 'Олена');
        expect(summary.lastName, 'Тест');
      },
    );

    test(
      'empty cityName + cityId set ⇒ summary.city resolved from taxonomy',
      () async {
        final container = _containerForUser(
          _userResolvableCity,
          cities: const [_kyivCity],
        );

        final summary = await container.read(clientProfileProvider.future);

        expect(
          summary.city,
          'Київ',
          reason:
              'when User.cityName is empty but cityId is set, the card resolves '
              'the display name from the location taxonomy by matching the id',
        );
        // No phoneNumber on this fixture → empty-string placeholder.
        expect(summary.phone, '');
      },
    );

    test(
      'cityId set but no taxonomy match ⇒ summary.city == "" (graceful fallback)',
      () async {
        // The fake serves a list that does NOT contain `city-missing`, so the
        // resolution loop finds no match and must fall back to '' without
        // throwing.
        final container = _containerForUser(
          _userUnresolvableCity,
          cities: const [_kyivCity],
        );

        final summary = await container.read(clientProfileProvider.future);

        expect(
          summary.city,
          '',
          reason:
              'when User.cityId references a city absent from the taxonomy, '
              'resolution must fall back to "" (placeholder path) rather than '
              'throwing',
        );
        expect(summary.phone, '');
      },
    );

    test(
      'no cityName and no cityId ⇒ summary.city == "" (placeholder path)',
      () async {
        final container = _containerForUser(_userNoCity);

        final summary = await container.read(clientProfileProvider.future);

        expect(
          summary.city,
          '',
          reason:
              'a CLIENT with no city must yield an empty string so the profile '
              'card renders its l10n placeholder instead of "null"',
        );
        expect(summary.phone, '');
      },
    );
  });

  // ── District-display branches (new feature) ───────────────────────────────
  //
  // RED-AGAINST-ABSENCE: before this feature clientProfile produced a city-only
  // label (`city: _resolveCityName(...)`), so the combined-label assertion below
  // ("Львів, Сихівський район") would FAIL — the provider would return the bare
  // "Львів". The first test therefore pins the new "<city>, <district>" wiring;
  // the remaining tests pin its graceful-degradation and fast-path contracts.
  group('clientProfile district label', () {
    test(
      'districtId set + district in taxonomy ⇒ '
      'summary.city == "Львів, Сихівський район"',
      () async {
        final container = _harnessForUser(
          _userLvivWithDistrict,
          cities: const [_lvivCity],
          districts: const [_sykhivDistrict],
        ).container;

        final summary = await container.read(clientProfileProvider.future);

        expect(
          summary.city,
          'Львів, Сихівський район',
          reason:
              'when the client has a resolvable city AND a districtId present '
              'in the taxonomy, the label composes "<city>, <district>"',
        );
      },
    );

    test(
      'districtId == null ⇒ summary.city == "Львів" (bare city, unchanged)',
      () async {
        final container = _harnessForUser(
          _userLvivNoDistrict,
          cities: const [_lvivCity],
          districts: const [_sykhivDistrict],
        ).container;

        final summary = await container.read(clientProfileProvider.future);

        expect(
          summary.city,
          'Львів',
          reason:
              'with no districtId the label stays the bare city — the district '
              'cascade is skipped entirely',
        );
      },
    );

    test(
      'districtId set but absent from taxonomy ⇒ graceful fallback to "Львів"',
      () async {
        // The fake serves a district list that does NOT contain
        // `district-missing`, so the resolution loop finds no match and must
        // degrade to the bare city without throwing.
        final container = _harnessForUser(
          _userLvivUnresolvableDistrict,
          cities: const [_lvivCity],
          districts: const [_sykhivDistrict],
        ).container;

        final summary = await container.read(clientProfileProvider.future);

        expect(
          summary.city,
          'Львів',
          reason:
              'a districtId that references a district absent from the taxonomy '
              'must degrade to the bare city, never throw and never blank the '
              'card',
        );
      },
    );

    test(
      'denormalized districtName ⇒ used WITHOUT a districtListProvider fetch',
      () async {
        final harness = _harnessForUser(
          _userLvivDenormDistrict,
          // No cities/districts seeded: both fast paths (cityName + districtName)
          // must short-circuit before any taxonomy fetch.
        );

        final summary = await harness.container.read(
          clientProfileProvider.future,
        );

        expect(
          summary.city,
          'Львів, Сихівський район',
          reason:
              'a non-empty denormalized districtName composes the combined '
              'label directly',
        );
        expect(
          harness.repo.fetchDistrictsCalls,
          0,
          reason:
              'the denormalized districtName fast path must NOT hit '
              'districtListProvider → fetchDistricts',
        );
      },
    );
  });
}
