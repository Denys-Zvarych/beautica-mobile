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

/// Fake [LocationRepository] returning a fixed city list for every oblast.
///
/// `clientProfile._resolveCityName` only reaches [fetchCities]; the oblast and
/// district methods are never exercised by these tests but throw if hit so a
/// stray dependency surfaces loudly instead of silently returning empty data.
class _FakeLocationRepository implements LocationRepository {
  const _FakeLocationRepository(this._cities);

  final List<City> _cities;

  @override
  Future<List<City>> fetchCities(String oblastId) async => _cities;

  @override
  Future<List<Oblast>> fetchOblasts() =>
      throw UnimplementedError('fetchOblasts not used in this test');

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) =>
      throw UnimplementedError('fetchDistricts not used in this test');
}

/// Builds a [ProviderContainer] wired with [user] and a fake location
/// repository serving [cities].
///
/// Holds [clientProfileProvider] alive with a no-op [ProviderContainer.listen]
/// subscription so the container is not torn down while the provider's future
/// is still loading.
ProviderContainer _containerForUser(
  User user, {
  List<City> cities = const <City>[],
}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(user)),
      locationRepositoryProvider.overrideWith(
        (_) => _FakeLocationRepository(cities),
      ),
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
  return container;
}

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
}
