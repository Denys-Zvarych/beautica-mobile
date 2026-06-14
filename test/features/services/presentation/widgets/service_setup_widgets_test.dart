// Regression test for the uniform-category-icon contract.
//
// BUG (fixed): `serviceCategoryIcon('MAKEUP')` previously returned
// `Icons.palette_rounded` while every other slug returned a different default.
// The fix collapsed all branches to a single constant `Icons.spa_rounded`.
//
// This test guards that contract: if anyone re-adds a per-slug branch that
// diverges (e.g. MAKEUP → Icons.palette_rounded), one or more cases below
// will fail with a clear inequality.

import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('serviceCategoryIcon', () {
    // The full set of representative slugs: known categories, an unknown slug,
    // a lowercase variant, and the empty string. Every case MUST return the
    // same IconData — there must be no per-slug branch in production.
    const List<String> allSlugs = <String>[
      'MAKEUP',
      'HAIR',
      'MANICURE',
      'PEDICURE',
      'FACE',
      'BODY',
      'BROWS_LASHES',
      'UNKNOWN_SLUG',
      'makeup', // lowercase variant
      '', // empty string
    ];

    test(
      'returns Icons.spa_rounded for every slug (uniform-icon contract)',
      () {
        for (final slug in allSlugs) {
          expect(
            serviceCategoryIcon(slug),
            equals(Icons.spa_rounded),
            reason:
                'serviceCategoryIcon("$slug") must return Icons.spa_rounded — '
                'all category slugs share one uniform glyph; per-slug branches '
                'are forbidden',
          );
        }
      },
    );

    test(
      'MAKEUP and HAIR return the same IconData (regression: palette_rounded divergence)',
      () {
        expect(
          serviceCategoryIcon('MAKEUP'),
          equals(serviceCategoryIcon('HAIR')),
          reason:
              'MAKEUP previously mapped to Icons.palette_rounded causing visual '
              'inconsistency; both must resolve to the same constant',
        );
      },
    );

    test('all representative slugs return the same IconData', () {
      final IconData reference = serviceCategoryIcon(allSlugs.first);
      for (final slug in allSlugs.skip(1)) {
        expect(
          serviceCategoryIcon(slug),
          equals(reference),
          reason:
              'serviceCategoryIcon("$slug") diverges from '
              'serviceCategoryIcon("${allSlugs.first}") — uniform-icon contract broken',
        );
      }
    });
  });
}
