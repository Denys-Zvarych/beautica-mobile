// Location-fix — clientProfile provider unit tests.
//
// The home hub derives [ClientProfileSummary] from the FRESH `GET /users/me`
// profile cached by [clientEditProfileProvider] (the same authoritative source
// the Settings edit screens read) — NOT from the long-lived `authProvider`
// session [User]. These tests pin the city/phone wiring against that source:
//   • cityName="Київ" / phoneNumber set ⇒ summary.city/phone reflect them
//     (fast path — no taxonomy fetch).
//   • cityName empty but cityId+oblastId set ⇒ summary.city resolves from the
//     location taxonomy (cityListProvider) by matching the city id.
//   • cityName empty AND no cityId/oblastId ⇒ summary.city == '' so the profile
//     card renders its placeholder path.
//   • an unauthenticated session ⇒ clientEditProfileProvider throws
//     [UnauthorizedFailure], which propagates as the card's AsyncError.
//
// `clientProfile` now transitively wires `cityListProvider` (a family that
// fetches via [LocationRepository]) to resolve the display name when the
// denormalized `User.cityName` is absent. The harness therefore overrides
// [locationRepositoryProvider] with a fake so the dependency graph resolves in
// test scope — mirroring the override style used across the location tests.
// Without it the still-loading `cityListProvider` leaf would dispose the whole
// graph mid-load (Riverpod 3.x: "disposed during loading state").
//
// Strategy: override [clientEditProfileProvider] with a stub whose `build()`
// returns the fixture [User] (i.e. drive the `/users/me` source directly), then
// read clientProfileProvider.future from a ProviderContainer (no widget tree). A
// keep-open `container.listen(...)` subscription holds the provider alive until
// its future settles so teardown never races the in-flight load. The
// unauthenticated path instead keeps the REAL [clientEditProfileProvider] and
// overrides [authProvider] to an unauthenticated session so the real auth gate
// fires.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// /users/me source stub
// ---------------------------------------------------------------------------

/// Stubs [clientEditProfileProvider] (the fresh `GET /users/me` source) to a
/// settled profile carrying [user]. `clientProfile` derives ONLY from this
/// provider, so driving it here is equivalent to the backend returning [user]
/// from `/users/me`.
class _StubClientEditProfile extends ClientEditProfile {
  _StubClientEditProfile(this._user);

  final User _user;

  @override
  Future<User> build() async => _user;
}

/// Stubs [clientEditProfileProvider] (the fresh `/users/me` source) to the same
/// failure the real provider raises when the session is unauthenticated — its
/// `build()` throws [UnauthorizedFailure] before ever calling `getMyProfile()`.
/// `clientProfile` must propagate that as its own AsyncError. (The auth-gate
/// behaviour itself — Unauthenticated ⇒ UnauthorizedFailure — is owned and
/// tested by clientEditProfileProvider; here we pin only clientProfile's
/// error-propagation contract, deterministically.)
class _UnauthorizedClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async => throw const UnauthorizedFailure();
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
typedef _Harness = ({
  ProviderContainer container,
  _FakeLocationRepository repo,
});

/// Builds a [ProviderContainer] wired with [user] (driven through the fresh
/// `/users/me` source [clientEditProfileProvider]) and a fake location
/// repository serving [cities] (and optionally [districts]).
///
/// Holds [clientProfileProvider] alive with a no-op [ProviderContainer.listen]
/// subscription so the container is not torn down while the provider's future
/// is still loading.
///
/// [clock] pins the injected `clockProvider` instant. It defaults to
/// [_kDefaultClockInstant] rather than being left un-overridden so that every
/// test in this file runs on ONE clock — `clientProfile` derives
/// `memberSinceYear` from that seam, and a provider reading the host clock
/// while the fixtures are fixed is precisely the incoherence Rule 4 of
/// `scripts/forbid_host_local_instant_anchor.sh` exists to catch. Always
/// anchor an override with `DateTime.utc(...)` or an explicit
/// `tz.TZDateTime(...)`, never a bare local `DateTime(...)` (see that script's
/// header).
_Harness _harnessForUser(
  User user, {
  List<City> cities = const <City>[],
  List<CityDistrict> districts = const <CityDistrict>[],
  DateTime? clock,
}) {
  final repo = _FakeLocationRepository(cities, districts: districts);
  final DateTime pinnedNow = clock ?? _kDefaultClockInstant;
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      clientEditProfileProvider.overrideWith(
        () => _StubClientEditProfile(user),
      ),
      locationRepositoryProvider.overrideWith((_) => repo),
      clockProvider.overrideWithValue(() => pinnedNow),
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
  DateTime? clock,
}) => _harnessForUser(user, cities: cities, clock: clock).container;

/// The instant every test in this file pins `clockProvider` to unless it asks
/// for another one.
///
/// Anchored with `DateTime.utc(...)` so the instant it names is a property of
/// the FIXTURE and not of whichever `TZ` the host process runs under — the dev
/// VM's own zone IS Europe/Kyiv, so a bare local `DateTime(...)` here would be
/// indistinguishable from a correct anchor locally while meaning something
/// different on CI. Noon UTC sits nowhere near a day boundary, so it round-trips
/// to the same Kyiv day from any realistic device zone; the boundary cases that
/// need otherwise pass their own `clock`.
final DateTime _kDefaultClockInstant = DateTime.utc(2026, 6, 14, 12);

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

    test('unauthenticated session ⇒ clientProfile surfaces UnauthorizedFailure '
        '(AsyncError from the /users/me source gate)', () async {
      // Drive the /users/me source (clientEditProfileProvider) to the failure it
      // raises on an unauthenticated session; clientProfile awaits that future,
      // so the failure must propagate as the card's AsyncError.
      //
      // `retry: (_, _) => null` disables Riverpod 3.x's default error-retry so
      // the thrown UnauthorizedFailure surfaces on the FIRST build instead of
      // looping the keepAlive source through endless retries (which would hang
      // `clientProfileProvider.future` until the test times out).
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          clientEditProfileProvider.overrideWith(
            _UnauthorizedClientEditProfile.new,
          ),
          locationRepositoryProvider.overrideWith(
            (_) => _FakeLocationRepository(const <City>[]),
          ),
          // Same pinned clock as every other container in this file — the
          // provider reads the seam before its first `await`, so it is read
          // even on the path that throws.
          clockProvider.overrideWithValue(() => _kDefaultClockInstant),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(clientProfileProvider.future),
        throwsA(isA<UnauthorizedFailure>()),
        reason:
            'an unauthenticated session must surface as UnauthorizedFailure '
            'through clientEditProfileProvider → clientProfile, never a hang '
            'or a blank card',
      );
    });
  });

  // ── District-display branches (new feature) ───────────────────────────────
  //
  // RED-AGAINST-ABSENCE: before this feature clientProfile produced a city-only
  // label (`city: _resolveCityName(...)`), so the combined-label assertion below
  // ("Львів, Сихівський район") would FAIL — the provider would return the bare
  // "Львів". The first test therefore pins the new "<city>, <district>" wiring;
  // the remaining tests pin its graceful-degradation and fast-path contracts.
  group('clientProfile district label', () {
    test('districtId set + district in taxonomy ⇒ '
        'summary.city == "Львів, Сихівський район"', () async {
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
    });

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

  // ── memberSinceYear is Kyiv-anchored, not device-anchored ─────────────────
  //
  // `clientProfile.memberSinceYear` used to be a raw `DateTime.now().year` —
  // a CALENDAR-FIELD read straight off the device clock, bypassing the
  // injected seam entirely (`lib/features/home/application/home_hub_notifier
  // .dart`). It now derives from `kyivToday(ref.watch(clockProvider))`.
  //
  // RED-AGAINST-ABSENCE, TWICE OVER. Both fixtures below pin a year that is
  // neither the real current year nor the device-zone year of the injected
  // instant, so:
  //   • the OLD implementation fails outright — it ignores the injected clock
  //     and reports whatever year the machine running the suite is in;
  //   • a naive "fixed" version that read the calendar fields off the injected
  //     instant WITHOUT the Kyiv conversion also fails — that is the device
  //     year, asserted explicitly below to be different.
  // Only the Kyiv-anchored derivation satisfies both.
  //
  // HOST-ZONE INDEPENDENT BY CONSTRUCTION. Each instant is anchored with
  // `DateTime.utc(...)` or an explicit `tz.TZDateTime(...)` location, so the
  // divergence each case exercises is a property of the FIXTURE. Verified
  // green under TZ=Europe/Kyiv (the dev VM, where this class of bug hides),
  // TZ=UTC, and TZ=Pacific/Honolulu (UTC−10 — the zone that actually exposed
  // this class earlier in this chain; Kyiv/UTC/Tokyo all agreed).
  group('clientProfile memberSinceYear (Kyiv-anchored)', () {
    test('device behind Kyiv across New Year ⇒ year is the KYIV year, not the '
        'device year', () async {
      // 2024-12-31 22:30 UTC is 2025-01-01 00:30 in Kyiv (EET, UTC+2 in
      // winter). The Kyiv YEAR is therefore 2025 while the injected instant's
      // own device-zone year is still 2024 — and both differ from the real
      // year the suite is executing in, so neither the old device-clock read
      // nor an unconverted read of the injected instant can pass this.
      final DateTime deviceNow = DateTime.utc(2024, 12, 31, 22, 30);

      final container = _containerForUser(_userWithCity, clock: deviceNow);

      final summary = await container.read(clientProfileProvider.future);

      expect(
        summary.memberSinceYear,
        2025,
        reason:
            'memberSinceYear must be the Europe/Kyiv calendar year the '
            'injected instant falls in — Kyiv had already rolled over to 2025 '
            'at 2024-12-31 22:30 UTC.',
      );
      expect(
        deviceNow.year,
        2024,
        reason:
            'the injected instant sits BEHIND Kyiv, so reading its calendar '
            'year directly (no Kyiv conversion) would report 2024 — this '
            'pins that the two genuinely disagree, so the assertion above is '
            'not vacuous.',
      );
    });

    test('device ahead of Kyiv across New Year ⇒ year is the KYIV year, not '
        'the device year', () async {
      // The mirror direction, anchored to the IANA `Asia/Tokyo` location
      // (UTC+9, no DST) rather than the host process's own TZ. Tokyo
      // 2025-01-01 06:00 is 2024-12-31 21:00 UTC, which is 2024-12-31 23:00 in
      // Kyiv — the device has rolled into 2025 while Kyiv is still in 2024.
      final DateTime deviceNow = tz.TZDateTime(
        tz.getLocation('Asia/Tokyo'),
        2025,
        1,
        1,
        6,
        0,
      );

      final container = _containerForUser(_userWithCity, clock: deviceNow);

      final summary = await container.read(clientProfileProvider.future);

      expect(
        summary.memberSinceYear,
        2024,
        reason:
            'memberSinceYear must follow Kyiv, which is still in 2024 when a '
            'UTC+9 device has already rolled over to 2025.',
      );
      expect(
        deviceNow.year,
        2025,
        reason:
            'the injected instant sits AHEAD of Kyiv, so reading its calendar '
            'year directly would report 2025 — the two genuinely disagree.',
      );
    });

    test('non-boundary instant ⇒ year matches on every zone', () async {
      // Noon UTC mid-year: Kyiv, UTC and every realistic device zone agree, so
      // this is the control case — it pins that the seam does not perturb the
      // ordinary path.
      final container = _containerForUser(_userWithCity);

      final summary = await container.read(clientProfileProvider.future);

      expect(summary.memberSinceYear, 2026);
    });
  });
}
