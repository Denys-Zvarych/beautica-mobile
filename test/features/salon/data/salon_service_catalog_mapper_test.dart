// Regression — SalonServiceCatalogMapper.fromDto displayName mapping.
//
// WHY THIS FILE EXISTS
// ---------------------
// The public salon profile's services accordion was rendering raw
// platform-category slugs (e.g. "HARDWARE_COSMETOLOGY") instead of the
// Ukrainian display name ("Апаратна косметологія") because
// [SalonServiceCategoryEntry] only ever carried the raw `category` field —
// the widget had nothing else to render. The fix added a required
// `displayName` field to the domain entity and wired
// [SalonServiceCatalogMapper.fromDto] to read `group.displayName` off the
// DTO (falling back to the raw `category` slug only when the server field is
// somehow null).
//
// The three test files touched alongside that fix
// (`salon_tab_providers_keepalive_test.dart`,
// `public_salon_profile_screen_test.dart`,
// `salon_services_accordion_test.dart`) only had their fixture constructors
// patched to compile against the new required constructor arg — every
// fixture sets `displayName` to the SAME value as `category`, so none of
// them can distinguish "renders displayName" from "renders category". A
// regression that silently swapped `displayName: group.displayName ?? category`
// back to `displayName: category` would pass every one of those suites.
//
// This file closes that gap at the actual translation boundary: it uses
// DISTINCT `category`/`displayName` values so the assertion can only pass if
// the mapper reads the DTO's `displayName` field, not its `category` field.
//
// Pure Dart unit test: no widget tree, no network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/salon/data/salon_mapper.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// One category group with DISTINCT `category` (raw slug) and `displayName`
/// (Ukrainian label) values — the exact shape that would expose the
/// raw-slug-instead-of-displayName regression.
SalonServiceCatalogResponse _distinctDisplayNameDto() =>
    SalonServiceCatalogResponse(
      (b) => b
        ..categories.add(
          SalonServiceCategoryGroup(
            (g) => g
              ..category = 'HARDWARE_COSMETOLOGY'
              ..displayName = 'Апаратна косметологія'
              ..count = 1
              ..services.add(
                ServiceDefinitionResponse(
                  (s) => s
                    ..id = 'svc-1'
                    ..name = 'Чистка обличчя'
                    ..category = 'HARDWARE_COSMETOLOGY'
                    ..baseDurationMinutes = 60
                    ..priceDisplay = '800 грн',
                ),
              ),
          ),
        ),
    );

/// A category group whose `displayName` is absent from the wire payload —
/// exercises the mapper's defensive fallback to the raw `category` slug.
SalonServiceCatalogResponse _missingDisplayNameDto() =>
    SalonServiceCatalogResponse(
      (b) => b
        ..categories.add(
          SalonServiceCategoryGroup(
            (g) => g
              ..category = 'NAIL_SERVICE'
              ..count = 0,
          ),
        ),
    );

void main() {
  group('SalonServiceCatalogMapper.fromDto', () {
    test('maps the entry displayName from the DTO displayName field, '
        'not the raw category slug', () {
      final List<SalonServiceCategoryEntry> result =
          SalonServiceCatalogMapper.fromDto(_distinctDisplayNameDto());

      expect(result, hasLength(1));
      final SalonServiceCategoryEntry entry = result.single;

      expect(
        entry.category,
        'HARDWARE_COSMETOLOGY',
        reason: 'the raw slug must still be carried through unchanged',
      );
      expect(
        entry.displayName,
        'Апаратна косметологія',
        reason:
            'displayName must come from the DTO\'s displayName field — '
            'this is the exact assertion the original raw-slug bug '
            'violated, and the one a regression back to '
            '`displayName: category` would fail.',
      );
      expect(
        entry.displayName,
        isNot(equals(entry.category)),
        reason:
            'displayName and category are DISTINCT on this fixture; if a '
            'future change collapses the mapper back to '
            '`displayName: category`, this equality would silently start '
            'passing and must fail instead.',
      );
    });

    test(
      'falls back to the raw category slug when the DTO displayName is null',
      () {
        final List<SalonServiceCategoryEntry> result =
            SalonServiceCatalogMapper.fromDto(_missingDisplayNameDto());

        expect(result, hasLength(1));
        final SalonServiceCategoryEntry entry = result.single;

        expect(entry.category, 'NAIL_SERVICE');
        expect(
          entry.displayName,
          'NAIL_SERVICE',
          reason:
              'when the server omits displayName, the mapper must fall '
              'back to the raw category slug rather than leaving the '
              'label null, blank, or throwing.',
        );
      },
    );

    test('returns an empty list when the DTO has no categories', () {
      final SalonServiceCatalogResponse dto = SalonServiceCatalogResponse(
        (b) => b,
      );

      expect(SalonServiceCatalogMapper.fromDto(dto), isEmpty);
    });
  });
}
