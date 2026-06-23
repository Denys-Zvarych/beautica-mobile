// Phase 13.3 — Unit tests for [SearchFiltersController] + the sibling
// [SearchFilterLabelsController].
//
// Pure-Dart provider units: no widget tree. Each test builds a fresh
// [ProviderContainer] (disposed in addTearDown) so keepAlive controller state
// never leaks between cases.
//
// Coverage:
//   SearchFiltersController
//     • initial state is const SearchFilters()
//     • setQuery — trims, blank/whitespace → null, real value kept
//     • selectCity — sets cityId (+ districtId); clearing cityId clears district
//     • toggleServiceType — single-select replaces prior; re-tap clears
//     • setMaxPrice — sets maxPrice; >= kSearchPriceCeiling → null boundary;
//       null → null; minPrice always stays null (single-thumb control)
//     • reset — back to const SearchFilters()
//     • logout reset — flipping authProvider to Unauthenticated rebuilds the
//       controller to const SearchFilters() (the keepAlive per-user self-clear)
//   SearchFilterLabelsController
//     • labels live OUT of SearchFilters (no label fields on the wire model);
//       set/clear cityName + categoryName independently; reset clears both

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

const _unauthenticated = AsyncData<AuthSession>(AuthSession.unauthenticated());

// ---------------------------------------------------------------------------
// A mutable AuthNotifier stub. Unlike the fixed-state stub, [emit] lets a test
// flip the settled session AFTER build() so a watcher (the search controllers)
// rebuilds — exercising the logout self-clear contract.
// ---------------------------------------------------------------------------

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AsyncValue<AuthSession> _initial;

  @override
  Future<AuthSession> build() async {
    state = _initial;
    return _initial.value ?? const AuthSession.unauthenticated();
  }

  void emit(AsyncValue<AuthSession> next) => state = next;
}

/// Builds a fresh container with the auth graph stubbed to [auth].
///
/// Returns the container AND the mutable auth notifier handle so a test can
/// flip the session mid-flight (logout reset). The container is disposed via
/// addTearDown so keepAlive controller state never leaks across tests.
({ProviderContainer container, _MutableAuthNotifier auth}) _make({
  AsyncValue<AuthSession> auth = _authenticated,
}) {
  final notifier = _MutableAuthNotifier(auth);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => notifier),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, auth: notifier);
}

SearchFiltersController _filters(ProviderContainer c) =>
    c.read(searchFiltersControllerProvider.notifier);

SearchFilters _state(ProviderContainer c) =>
    c.read(searchFiltersControllerProvider);

void main() {
  group('SearchFiltersController — initial', () {
    test('starts at an empty const SearchFilters()', () {
      final c = _make().container;
      expect(_state(c), const SearchFilters());
    });
  });

  group('SearchFiltersController.setQuery', () {
    test('keeps a trimmed non-blank value', () {
      final c = _make().container;

      _filters(c).setQuery('  манікюр  ');

      expect(_state(c).query, 'манікюр');
    });

    test('normalises an empty string to null', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр'); // first set a value

      _filters(c).setQuery('');

      expect(_state(c).query, isNull);
    });

    test('normalises a whitespace-only string to null', () {
      final c = _make().container;

      _filters(c).setQuery('   ');

      expect(_state(c).query, isNull);
    });

    test('normalises a null query to null', () {
      final c = _make().container;
      _filters(c).setQuery('х');

      _filters(c).setQuery(null);

      expect(_state(c).query, isNull);
    });
  });

  group('SearchFiltersController.selectCity', () {
    test('sets cityId with no district', () {
      final c = _make().container;

      _filters(c).selectCity(cityId: 'city-kyiv');

      expect(_state(c).cityId, 'city-kyiv');
      expect(_state(c).districtId, isNull);
    });

    test('sets cityId AND districtId together', () {
      final c = _make().container;

      _filters(c).selectCity(cityId: 'city-kyiv', districtId: 'dist-1');

      expect(_state(c).cityId, 'city-kyiv');
      expect(_state(c).districtId, 'dist-1');
    });

    test('clearing the city (cityId: null) also clears the district', () {
      final c = _make().container;
      _filters(c).selectCity(cityId: 'city-kyiv', districtId: 'dist-1');

      _filters(c).selectCity(cityId: null);

      expect(_state(c).cityId, isNull);
      expect(
        _state(c).districtId,
        isNull,
        reason: 'a district is meaningless without its city — must be cleared',
      );
    });

    test('a districtId passed with a null cityId is dropped', () {
      final c = _make().container;

      _filters(c).selectCity(cityId: null, districtId: 'dist-orphan');

      expect(_state(c).cityId, isNull);
      expect(_state(c).districtId, isNull);
    });
  });

  group('SearchFiltersController.toggleServiceType', () {
    test('selecting a category sets categoryKey', () {
      final c = _make().container;

      _filters(c).toggleServiceType('NAILS');

      expect(_state(c).categoryKey, 'NAILS');
    });

    test(
      'selecting a different category REPLACES the prior (single-select)',
      () {
        final c = _make().container;
        _filters(c).toggleServiceType('NAILS');

        _filters(c).toggleServiceType('BROWS');

        expect(_state(c).categoryKey, 'BROWS');
      },
    );

    test('re-tapping the selected category clears it', () {
      final c = _make().container;
      _filters(c).toggleServiceType('NAILS');

      _filters(c).toggleServiceType('NAILS');

      expect(_state(c).categoryKey, isNull);
    });
  });

  group('SearchFiltersController.setMaxPrice', () {
    test('sets an in-range ceiling', () {
      final c = _make().container;

      _filters(c).setMaxPrice(1200);

      expect(_state(c).maxPrice, 1200);
    });

    test('a value AT the ceiling collapses to null ("будь-яка")', () {
      final c = _make().container;

      _filters(c).setMaxPrice(kSearchPriceCeiling);

      expect(
        _state(c).maxPrice,
        isNull,
        reason: 'value == kSearchPriceCeiling means no upper bound',
      );
    });

    test('a value ABOVE the ceiling collapses to null', () {
      final c = _make().container;

      _filters(c).setMaxPrice(kSearchPriceCeiling + 500);

      expect(_state(c).maxPrice, isNull);
    });

    test('a value just BELOW the ceiling is kept', () {
      final c = _make().container;

      _filters(c).setMaxPrice(kSearchPriceCeiling - 100);

      expect(_state(c).maxPrice, kSearchPriceCeiling - 100);
    });

    test('null clears the ceiling', () {
      final c = _make().container;
      _filters(c).setMaxPrice(1000);

      _filters(c).setMaxPrice(null);

      expect(_state(c).maxPrice, isNull);
    });

    test('the single-thumb control never sets minPrice', () {
      final c = _make().container;

      _filters(c).setMaxPrice(1000);

      expect(
        _state(c).minPrice,
        isNull,
        reason: 'setMaxPrice must leave minPrice null (single-thumb slider)',
      );
    });
  });

  group('SearchFiltersController.reset', () {
    test('clears every populated field back to const SearchFilters()', () {
      final c = _make().container;
      _filters(c)
        ..setQuery('манікюр')
        ..selectCity(cityId: 'city-kyiv', districtId: 'dist-1')
        ..toggleServiceType('NAILS')
        ..setMaxPrice(1200);
      // Precondition: state is genuinely non-empty.
      expect(_state(c), isNot(const SearchFilters()));

      _filters(c).reset();

      expect(_state(c), const SearchFilters());
    });
  });

  group('SearchFiltersController — logout self-clear', () {
    test('rebuilds to const SearchFilters() when the session goes '
        'Unauthenticated', () {
      final made = _make(auth: _authenticated);
      final c = made.container;

      // Populate a filter set on the authenticated session.
      _filters(c)
        ..selectCity(cityId: 'city-kyiv')
        ..toggleServiceType('NAILS')
        ..setMaxPrice(900);
      expect(_state(c).cityId, 'city-kyiv');

      // Flip the watched authProvider to Unauthenticated (logout).
      made.auth.emit(_unauthenticated);

      // The keepAlive controller watches authProvider, so build() re-runs and
      // the per-user filter set is shed — no manual eviction needed.
      expect(
        _state(c),
        const SearchFilters(),
        reason: 'a fresh session must not inherit the prior user\'s search',
      );
    });
  });

  group('SearchFilterLabelsController', () {
    test('starts empty (both labels null)', () {
      final c = _make().container;
      final labels = c.read(searchFilterLabelsControllerProvider);

      expect(labels.cityName, isNull);
      expect(labels.categoryName, isNull);
    });

    test('sets and clears the city + category labels independently', () {
      final c = _make().container;
      final notifier = c.read(searchFilterLabelsControllerProvider.notifier);

      notifier.setCityName('Львів');
      notifier.setCategoryName('Манікюр');
      var labels = c.read(searchFilterLabelsControllerProvider);
      expect(labels.cityName, 'Львів');
      expect(labels.categoryName, 'Манікюр');

      // Clearing the category leaves the city untouched.
      notifier.setCategoryName(null);
      labels = c.read(searchFilterLabelsControllerProvider);
      expect(labels.categoryName, isNull);
      expect(labels.cityName, 'Львів');
    });

    test('reset clears both labels', () {
      final c = _make().container;
      final notifier = c.read(searchFilterLabelsControllerProvider.notifier);
      notifier.setCityName('Львів');
      notifier.setCategoryName('Манікюр');

      notifier.reset();

      final labels = c.read(searchFilterLabelsControllerProvider);
      expect(labels.cityName, isNull);
      expect(labels.categoryName, isNull);
    });

    test('labels are NOT mirrored onto SearchFilters (separate model)', () {
      final c = _make().container;

      c.read(searchFilterLabelsControllerProvider.notifier)
        ..setCityName('Львів')
        ..setCategoryName('Манікюр');

      // SearchFilters carries ids/slugs only — setting display labels must not
      // touch the wire model.
      expect(_state(c), const SearchFilters());
    });
  });

  // -------------------------------------------------------------------------
  // SearchServiceSelectionController — the Variant A («Рейка + послуги»)
  // second-level service-chip selection set. Multi-select; reset imperatively
  // on a category change AND automatically on a session flip (logout/login).
  // -------------------------------------------------------------------------
  group('SearchServiceSelectionController', () {
    Set<String> selection(ProviderContainer c) =>
        c.read(searchServiceSelectionControllerProvider);
    SearchServiceSelectionController notifier(ProviderContainer c) =>
        c.read(searchServiceSelectionControllerProvider.notifier);

    test('starts as an empty set', () {
      final c = _make().container;
      expect(selection(c), isEmpty);
    });

    test('toggle adds a key when absent', () {
      final c = _make().container;

      notifier(c).toggle('haircut');

      expect(selection(c), <String>{'haircut'});
    });

    test('toggle is multi-select — distinct keys accumulate', () {
      final c = _make().container;

      notifier(c)
        ..toggle('haircut')
        ..toggle('coloring');

      expect(selection(c), <String>{'haircut', 'coloring'});
    });

    test('toggle removes a key when already present', () {
      final c = _make().container;
      notifier(c).toggle('haircut');

      notifier(c).toggle('haircut');

      expect(selection(c), isEmpty);
    });

    test('clear drops every selected service', () {
      final c = _make().container;
      notifier(c)
        ..toggle('haircut')
        ..toggle('coloring');
      expect(selection(c), isNotEmpty);

      notifier(c).clear();

      expect(selection(c), isEmpty);
    });

    test('rebuilds to an empty set when the session goes Unauthenticated', () {
      final made = _make(auth: _authenticated);
      final c = made.container;

      notifier(c)
        ..toggle('haircut')
        ..toggle('coloring');
      expect(selection(c), isNotEmpty);

      // Flip the watched authProvider to Unauthenticated (logout). The keepAlive
      // controller watches authProvider, so build() re-runs and the per-user
      // service selection is shed — mirroring SearchFiltersController.
      made.auth.emit(_unauthenticated);

      expect(
        selection(c),
        isEmpty,
        reason: 'a fresh session must not inherit the prior user\'s services',
      );
    });
  });
}
