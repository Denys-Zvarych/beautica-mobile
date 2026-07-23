// Phase 13.4 — Unit suite for [SearchFilters.activeFilterCount].
//
// The results top-bar «(N)» badge is driven directly by this getter, so its
// arithmetic is the contract the badge widget renders. Pure Dart — no widgets,
// no providers. Pins: an empty set is 0; each facet contributes exactly 1; the
// price band counts ONCE whether only a min, only a max, or both are set; the
// per-service slug set counts ONCE when non-empty and 0 when empty; query/sort
// are NOT facets; a fully-populated filter maxes out at 6.

import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchFilters.activeFilterCount', () {
    test('an empty filter set counts 0 facets', () {
      expect(const SearchFilters().activeFilterCount, 0);
    });

    test('a non-default sort alone is NOT a facet (stays 0)', () {
      // sort is always forwarded but never surfaced as a clearable filter.
      expect(
        const SearchFilters(sort: SearchSort.priceAsc).activeFilterCount,
        0,
      );
    });

    test('a free-text query alone is NOT a facet (stays 0)', () {
      // query is not a clearable chip on the results screen → not counted.
      expect(const SearchFilters(query: 'Манікюр').activeFilterCount, 0);
    });

    test('a minRating alone is NOT counted (not surfaced as a facet)', () {
      expect(const SearchFilters(minRating: 4).activeFilterCount, 0);
    });

    group('each single facet contributes exactly 1', () {
      test('region (oblastId)', () {
        expect(const SearchFilters(oblastId: 'o1').activeFilterCount, 1);
      });

      test('city (cityId)', () {
        expect(const SearchFilters(cityId: 'c1').activeFilterCount, 1);
      });

      test('district (districtId)', () {
        expect(const SearchFilters(districtId: 'd1').activeFilterCount, 1);
      });

      test('category (categoryKey)', () {
        expect(const SearchFilters(categoryKey: 'HAIR').activeFilterCount, 1);
      });

      test('a non-empty serviceTypeSlugs set', () {
        expect(
          const SearchFilters(
            serviceTypeSlugs: <String>{'manicure'},
          ).activeFilterCount,
          1,
        );
      });
    });

    group('the per-service slug set counts ONCE regardless of size', () {
      test('an empty slug set adds 0', () {
        expect(
          const SearchFilters(serviceTypeSlugs: <String>{}).activeFilterCount,
          0,
        );
      });

      test('multiple slugs still count as a single facet', () {
        expect(
          const SearchFilters(
            serviceTypeSlugs: <String>{'manicure', 'pedicure', 'gel'},
          ).activeFilterCount,
          1,
        );
      });
    });

    group('the price band counts ONCE', () {
      test('only a min price counts 1', () {
        expect(const SearchFilters(minPrice: 100).activeFilterCount, 1);
      });

      test('only a max price counts 1', () {
        expect(const SearchFilters(maxPrice: 900).activeFilterCount, 1);
      });

      test('both a min AND a max still count 1 (one band, not two)', () {
        expect(
          const SearchFilters(minPrice: 100, maxPrice: 900).activeFilterCount,
          1,
        );
      });
    });

    test(
      'boundary: a category set but an EMPTY slug set counts the category only '
      '(1, not 2)',
      () {
        expect(
          const SearchFilters(
            categoryKey: 'NAILS',
            serviceTypeSlugs: <String>{},
          ).activeFilterCount,
          1,
        );
      },
    );

    test('a category WITH a non-empty slug set counts both facets (2)', () {
      expect(
        const SearchFilters(
          categoryKey: 'NAILS',
          serviceTypeSlugs: <String>{'manicure'},
        ).activeFilterCount,
        2,
      );
    });

    test('a fully-populated filter maxes out at 6 facets', () {
      // All six clearable facets set + the non-facet query/sort/minRating that
      // must NOT inflate the count beyond 6.
      const filters = SearchFilters(
        query: 'Манікюр',
        oblastId: 'o1',
        cityId: 'c1',
        districtId: 'd1',
        categoryKey: 'NAILS',
        serviceTypeSlugs: <String>{'manicure', 'pedicure'},
        minPrice: 100,
        maxPrice: 900,
        minRating: 4,
        sort: SearchSort.priceDesc,
      );
      expect(filters.activeFilterCount, 6);
    });
  });
}
