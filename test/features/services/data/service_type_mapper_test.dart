// Phase 16.2 — Unit tests for [ServiceTypeMapper].
//
// Pure-Dart translation from the generated slug-contract DTO
// [PlatformServiceTypeResponse] to the domain [ServiceTypeOption].
//
// Coverage:
//   1. fromDto — total mapping: id/slug/nameUk/categoryName all populated.
//   2. fromDto — nullable wire fields fall back to '' (mapper never throws).
//   3. fromDtoList — drops rows with empty id.
//   4. fromDtoList — drops rows with empty slug.
//   5. fromDtoList — keeps only fully-selectable rows; preserves order.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/services/data/service_type_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Builds a [PlatformServiceTypeResponse]. Any argument left null is omitted
/// from the builder, reproducing an absent wire field.
PlatformServiceTypeResponse _dto({
  String? id = 'type-1',
  String? slug = 'CLASSIC_LASHES',
  String? nameUk = 'Класичне нарощування',
  String? categoryName = 'EYELASH',
}) => PlatformServiceTypeResponse(
  (b) => b
    ..id = id
    ..slug = slug
    ..nameUk = nameUk
    ..categoryName = categoryName,
);

void main() {
  group('ServiceTypeMapper.fromDto', () {
    test('maps every field on a fully-populated DTO', () {
      final option = ServiceTypeMapper.fromDto(_dto());

      expect(option.id, 'type-1');
      expect(option.slug, 'CLASSIC_LASHES');
      expect(option.nameUk, 'Класичне нарощування');
      expect(option.categoryName, 'EYELASH');
    });

    test('substitutes empty strings for every null wire field', () {
      final option = ServiceTypeMapper.fromDto(
        _dto(id: null, slug: null, nameUk: null, categoryName: null),
      );

      expect(option.id, '');
      expect(option.slug, '');
      expect(option.nameUk, '');
      expect(option.categoryName, '');
    });

    test('substitutes empty string for a single absent field only', () {
      final option = ServiceTypeMapper.fromDto(_dto(nameUk: null));

      expect(option.id, 'type-1');
      expect(option.slug, 'CLASSIC_LASHES');
      expect(option.nameUk, ''); // absent → fallback
      expect(option.categoryName, 'EYELASH');
    });
  });

  group('ServiceTypeMapper.fromDtoList', () {
    test('maps a list of selectable rows preserving order', () {
      final result =
          ServiceTypeMapper.fromDtoList(<PlatformServiceTypeResponse>[
            _dto(id: 'type-1', slug: 'CLASSIC_LASHES', nameUk: 'Класика'),
            _dto(id: 'type-2', slug: 'VOLUME_LASHES', nameUk: 'Об’ємне'),
          ]);

      expect(result.map((o) => o.id).toList(), <String>['type-1', 'type-2']);
      expect(result.map((o) => o.slug).toList(), <String>[
        'CLASSIC_LASHES',
        'VOLUME_LASHES',
      ]);
    });

    test('drops a row whose id is absent (empty after fallback)', () {
      final result = ServiceTypeMapper.fromDtoList(
        <PlatformServiceTypeResponse>[
          _dto(id: null, slug: 'VOLUME_LASHES'), // unselectable — no id
          _dto(id: 'type-2', slug: 'CLASSIC_LASHES'),
        ],
      );

      expect(result.length, 1);
      expect(result.single.id, 'type-2');
    });

    test('drops a row whose slug is absent (empty after fallback)', () {
      final result = ServiceTypeMapper.fromDtoList(
        <PlatformServiceTypeResponse>[
          _dto(id: 'type-1', slug: null), // unselectable — no slug
          _dto(id: 'type-2', slug: 'CLASSIC_LASHES'),
        ],
      );

      expect(result.length, 1);
      expect(result.single.slug, 'CLASSIC_LASHES');
    });

    test('returns empty when every row is unselectable', () {
      final result =
          ServiceTypeMapper.fromDtoList(<PlatformServiceTypeResponse>[
            _dto(id: null, slug: null),
            _dto(id: 'only-id', slug: null),
            _dto(id: null, slug: 'ONLY_SLUG'),
          ]);

      expect(result, isEmpty);
    });

    test('returns empty for an empty input', () {
      expect(
        ServiceTypeMapper.fromDtoList(const <PlatformServiceTypeResponse>[]),
        isEmpty,
      );
    });
  });
}
