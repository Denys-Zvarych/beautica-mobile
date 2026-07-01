// Phase 13.4 — Unit tests for the MIN/MAX two-thumb price-filter invariant on
// [SearchFiltersController].
//
// The single-thumb price control was replaced by a two-thumb range: a lower
// bound (setMinPrice / left thumb / MIN field) and an upper bound (setMaxPrice /
// right thumb / MAX field), plus the atomic [setPriceRange] a slider drag uses.
// The sibling search_filters_controller_test.dart predates this redesign and
// only covers the old single-thumb setMaxPrice (and asserts minPrice stays
// null). THIS file owns the new surface the redesign introduced:
//
//   1. min <= max enforcement (the controller can never emit a 400-able inverted
//      pair): raising MIN above MAX pushes/clears MAX; lowering MAX below MIN
//      pulls MIN down; setPriceRange collapses an inverted finite pair.
//   2. clamp-to-ceiling / clear-edges: max >= ceiling → cleared (no upper
//      bound); min <= 0 → cleared (no lower bound); out-of-range inputs clamped.
//
// Pure-Dart provider units: no widget tree. Each test builds a fresh
// [ProviderContainer] (disposed in addTearDown) so keepAlive controller state
// never leaks between cases — mirroring the sibling controller test.

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

/// Stubs authProvider with a fixed settled session so the keepAlive search
/// controller builds cleanly to const SearchFilters().
class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

ProviderContainer _make() {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FixedAuthNotifier.new),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

SearchFiltersController _filters(ProviderContainer c) =>
    c.read(searchFiltersControllerProvider.notifier);

SearchFilters _state(ProviderContainer c) =>
    c.read(searchFiltersControllerProvider);

void main() {
  // -------------------------------------------------------------------------
  // GAP 2 — clamp-to-ceiling / clear edges on the NEW lower bound (setMinPrice)
  // and the atomic setPriceRange. (setMaxPrice's own ceiling/null edges are
  // already covered by the sibling single-thumb test.)
  // -------------------------------------------------------------------------
  group('SearchFiltersController.setMinPrice — clamp & clear edges', () {
    test('sets an in-range lower bound', () {
      final c = _make();

      _filters(c).setMinPrice(300);

      expect(_state(c).minPrice, 300);
    });

    test('a value <= 0 clears the lower bound (no lower bound)', () {
      final c = _make();
      _filters(c).setMinPrice(300); // first establish a floor

      _filters(c).setMinPrice(0);

      expect(
        _state(c).minPrice,
        isNull,
        reason: 'minPrice <= 0 means no lower bound — must clear',
      );
    });

    test('a negative value clears the lower bound', () {
      final c = _make();

      _filters(c).setMinPrice(-50);

      expect(_state(c).minPrice, isNull);
    });

    test('null clears the lower bound', () {
      final c = _make();
      _filters(c).setMinPrice(400);

      _filters(c).setMinPrice(null);

      expect(_state(c).minPrice, isNull);
    });

    test('an over-ceiling lower bound is clamped to the ceiling', () {
      final c = _make();

      _filters(c).setMinPrice(kSearchPriceCeiling + 1000);

      // Clamped to the ceiling (not cleared — a floor at the ceiling is a valid,
      // if narrow, lower bound; only the UPPER bound collapses at the ceiling).
      expect(_state(c).minPrice, kSearchPriceCeiling);
    });
  });

  group('SearchFiltersController.setPriceRange — clamp & clear edges', () {
    test('keeps an in-range finite pair', () {
      final c = _make();

      _filters(c).setPriceRange(min: 300, max: 900);

      expect(_state(c).minPrice, 300);
      expect(_state(c).maxPrice, 900);
    });

    test(
      'min <= 0 clears the lower bound; max >= ceiling clears the upper',
      () {
        final c = _make();

        _filters(c).setPriceRange(min: 0, max: kSearchPriceCeiling);

        expect(_state(c).minPrice, isNull, reason: 'min 0 → no lower bound');
        expect(
          _state(c).maxPrice,
          isNull,
          reason: 'max at ceiling → no upper bound («будь-яка»)',
        );
      },
    );

    test(
      'out-of-range bounds are clamped (min<0 cleared, max>ceiling cleared)',
      () {
        final c = _make();

        _filters(c).setPriceRange(min: -100, max: kSearchPriceCeiling + 500);

        expect(_state(c).minPrice, isNull);
        expect(_state(c).maxPrice, isNull);
      },
    );

    test('a null/null pair clears both bounds', () {
      final c = _make();
      _filters(c).setPriceRange(min: 300, max: 900);

      _filters(c).setPriceRange(min: null, max: null);

      expect(_state(c).minPrice, isNull);
      expect(_state(c).maxPrice, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // GAP 1 — the min <= max invariant. The controller enforces it atomically at
  // every boundary so the UI can never emit an inverted pair the backend would
  // reject with a 400.
  // -------------------------------------------------------------------------
  group('SearchFiltersController — min <= max invariant (setMinPrice)', () {
    test('raising MIN above a finite MAX pushes MAX up to match', () {
      final c = _make();
      _filters(c).setMaxPrice(600); // ceiling at 600

      _filters(c).setMinPrice(900); // floor now exceeds the ceiling

      expect(_state(c).minPrice, 900);
      expect(
        _state(c).maxPrice,
        900,
        reason: 'raising MIN above MAX must push MAX up so min <= max holds',
      );
    });

    test('raising MIN to/above the ceiling pushes MAX past the ceiling → '
        'cleared (no upper bound)', () {
      final c = _make();
      _filters(c).setMaxPrice(600);

      _filters(c).setMinPrice(kSearchPriceCeiling); // floor AT the ceiling

      expect(
        _state(c).minPrice,
        kSearchPriceCeiling,
        reason: 'a floor AT the ceiling is a valid (clamped) lower bound',
      );
      expect(
        _state(c).maxPrice,
        isNull,
        reason: 'MAX pushed to the ceiling collapses to «будь-яка» (no upper)',
      );
    });

    test('raising MIN below the current MAX leaves MAX untouched', () {
      final c = _make();
      _filters(c).setMaxPrice(900);

      _filters(c).setMinPrice(300);

      expect(_state(c).minPrice, 300);
      expect(
        _state(c).maxPrice,
        900,
        reason: 'min < max already holds — MAX must not move',
      );
    });
  });

  group('SearchFiltersController — min <= max invariant (setMaxPrice)', () {
    test('lowering MAX below a finite MIN pulls MIN down to match', () {
      final c = _make();
      _filters(c).setMinPrice(800); // floor at 800

      _filters(c).setMaxPrice(500); // ceiling now below the floor

      expect(_state(c).maxPrice, 500);
      expect(
        _state(c).minPrice,
        500,
        reason: 'lowering MAX below MIN must pull MIN down so min <= max holds',
      );
    });

    test('lowering MAX above the current MIN leaves MIN untouched', () {
      final c = _make();
      _filters(c).setMinPrice(300);

      _filters(c).setMaxPrice(900);

      expect(_state(c).minPrice, 300);
      expect(
        _state(c).maxPrice,
        900,
        reason: 'min < max already holds — MIN must not move',
      );
    });

    test('clearing MAX (null) with a finite MIN leaves MIN intact (no upper '
        'bound is >= any floor)', () {
      final c = _make();
      _filters(c).setMinPrice(400);

      _filters(c).setMaxPrice(null);

      expect(_state(c).minPrice, 400);
      expect(_state(c).maxPrice, isNull);
    });
  });

  group('SearchFiltersController — min <= max invariant (setPriceRange)', () {
    test(
      'an inverted finite pair (min > max) collapses to the lower value',
      () {
        final c = _make();

        // A single drag emitting an inverted pair (e.g. the thumbs crossed):
        // both finite, min > max → coalesced to the lower of the two.
        _filters(c).setPriceRange(min: 900, max: 300);

        expect(_state(c).minPrice, 300);
        expect(
          _state(c).maxPrice,
          300,
          reason:
              'an inverted finite pair collapses to the lower value (min<=max)',
        );
      },
    );

    test('a valid ordered pair is preserved as-is', () {
      final c = _make();

      _filters(c).setPriceRange(min: 200, max: 1500);

      expect(_state(c).minPrice, 200);
      expect(_state(c).maxPrice, 1500);
    });

    test('equal bounds (min == max) are a valid degenerate range', () {
      final c = _make();

      _filters(c).setPriceRange(min: 500, max: 500);

      expect(_state(c).minPrice, 500);
      expect(_state(c).maxPrice, 500);
    });
  });
}
