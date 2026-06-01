// Tests for [MasterServiceMapper].
//
// Strategy: pure Dart unit tests — no widget tree, no Riverpod container,
// no HTTP mocks required. [MasterServiceMapper] is a static-method-only
// abstract final class, so the private [_categoryEnum] helper is tested
// indirectly through [toCreateRequest].
//
// Coverage:
//   F-1 through F-7.  toCreateRequest maps each of the 7 wire names to the
//                     corresponding [CreateServiceDefinitionRequestCategoryEnum].
//   F-8.  category: null  → request.category == null.
//   F-9.  unknown wire    → fallback to OTHER.
//   G-1.  toUpdateBody includes category key when category is provided.
//   G-2.  toUpdateBody omits category key when category is null.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/services/data/master_service_mapper.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Builds a minimal [MasterServiceCreate] whose only variable field is [category].
MasterServiceCreate _createInput({String? category}) => MasterServiceCreate(
  name: 'x',
  durationMinutes: 30,
  price: 100.0,
  category: category,
);

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  // ── F. _categoryEnum via toCreateRequest ──────────────────────────────────

  group('F. toCreateRequest — category mapping via _categoryEnum', () {
    // F-1 through F-7: each known wire name maps to the matching enum constant.

    const knownMappings =
        <(String, CreateServiceDefinitionRequestCategoryEnum)>[
          ('MANICURE', CreateServiceDefinitionRequestCategoryEnum.MANICURE),
          ('PEDICURE', CreateServiceDefinitionRequestCategoryEnum.PEDICURE),
          ('EYELASH', CreateServiceDefinitionRequestCategoryEnum.EYELASH),
          ('HAIRCUT', CreateServiceDefinitionRequestCategoryEnum.HAIRCUT),
          ('MAKEUP', CreateServiceDefinitionRequestCategoryEnum.MAKEUP),
          ('BROWS', CreateServiceDefinitionRequestCategoryEnum.BROWS),
          ('OTHER', CreateServiceDefinitionRequestCategoryEnum.OTHER),
        ];

    for (final (wire, expectedEnum) in knownMappings) {
      test('wire "$wire" maps to $expectedEnum', () {
        final request = MasterServiceMapper.toCreateRequest(
          _createInput(category: wire),
        );
        expect(
          request.category,
          equals(expectedEnum),
          reason: 'wire name "$wire" must map to the $expectedEnum enum value',
        );
      });
    }

    // F-8: null category → request.category is null (field is optional).
    test('F-8. null category → request.category is null', () {
      final request = MasterServiceMapper.toCreateRequest(
        _createInput(category: null),
      );
      expect(
        request.category,
        isNull,
        reason: 'category must be absent from the request when input is null',
      );
    });

    // F-9: unrecognised wire name → fallback to OTHER.
    test('F-9. unknown wire name falls back to OTHER', () {
      final request = MasterServiceMapper.toCreateRequest(
        _createInput(category: 'UNKNOWN_WIRE'),
      );
      expect(
        request.category,
        equals(CreateServiceDefinitionRequestCategoryEnum.OTHER),
        reason:
            'unrecognised wire names must fall back to OTHER so the call '
            'never throws at the data boundary',
      );
    });
  });

  // ── G. toUpdateBody — category field inclusion / exclusion ────────────────

  group('G. toUpdateBody — category key in PATCH body', () {
    // G-1: category present in patch → body contains the 'category' key.
    test('G-1. includes category key when category is provided', () {
      final body = MasterServiceMapper.toUpdateBody(
        const MasterServiceUpdate(category: 'MAKEUP'),
      );
      expect(
        body.containsKey('category'),
        isTrue,
        reason: 'body must contain the category key when a value is provided',
      );
      expect(
        body['category'],
        equals('MAKEUP'),
        reason: 'body[category] must equal the provided wire name string',
      );
    });

    // G-2: no category in patch → body must NOT contain the 'category' key.
    test('G-2. omits category key when category is null (PATCH semantics)', () {
      final body = MasterServiceMapper.toUpdateBody(
        const MasterServiceUpdate(name: 'Тест'),
      );
      expect(
        body.containsKey('category'),
        isFalse,
        reason:
            'body must NOT contain the category key when it is null — '
            'the backend treats absent keys as "no change" (PATCH semantics)',
      );
    });
  });
}
