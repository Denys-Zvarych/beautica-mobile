// Tests for [MasterServiceMapper].
//
// Strategy: pure Dart unit tests — no widget tree, no Riverpod container,
// no HTTP mocks required. [MasterServiceMapper] is a static-method-only
// abstract final class.
//
// Coverage:
//   F-1 through F-7.  toCreateRequest passes each wire name through as a plain
//                     String on request.category (enum→String backend change).
//   F-8.  category: null  → request.category == null.
//   F-9.  arbitrary wire  → passed through verbatim (no longer coerced).
//   G-1.  toUpdateBody includes category key when category is provided.
//   G-2.  toUpdateBody omits category key when category is null.
//   H-1.  fromApprovedCategoryList maps name+displayName and drops blank names.

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
  // ── F. category String pass-through via toCreateRequest ───────────────────
  //
  // The backend changed CreateServiceDefinitionRequest.category from a strict
  // enum to a plain String, so the mapper now forwards the wire name verbatim
  // (no enum coercion, no OTHER fallback).

  group('F. toCreateRequest — category String pass-through', () {
    const wireNames = <String>[
      'MANICURE',
      'PEDICURE',
      'EYELASH',
      'HAIRCUT',
      'MAKEUP',
      'BROWS',
      'OTHER',
      // A dynamically-approved category that never existed as an enum constant.
      'NAIL_ART',
    ];

    for (final wire in wireNames) {
      test('wire "$wire" is forwarded verbatim as a String', () {
        final request = MasterServiceMapper.toCreateRequest(
          _createInput(category: wire),
        );
        expect(
          request.category,
          equals(wire),
          reason: 'category must be sent as the plain wire String "$wire"',
        );
      });
    }

    // F-8: null category → ArgumentError (backend requires category now).
    test('F-8. null category throws ArgumentError (category is required)', () {
      expect(
        () => MasterServiceMapper.toCreateRequest(_createInput(category: null)),
        throwsArgumentError,
        reason:
            'category is @NotBlank on the backend and non-nullable on the '
            'generated request — the mapper must fail fast when it is null',
      );
    });

    // F-9: an arbitrary previously-unknown wire name is passed through as-is.
    test('F-9. arbitrary wire name passes through unchanged', () {
      final request = MasterServiceMapper.toCreateRequest(
        _createInput(category: 'SOME_NEW_CATEGORY'),
      );
      expect(
        request.category,
        equals('SOME_NEW_CATEGORY'),
        reason:
            'dynamically-approved categories must pass through unchanged now '
            'that category is a String, not a fixed enum',
      );
    });
  });

  // ── H. fromApprovedCategoryList ───────────────────────────────────────────

  group('H. fromApprovedCategoryList — DTO → ServiceCategoryOption', () {
    ApprovedCategoryResponse approvedDto({String? name, String? displayName}) =>
        (ApprovedCategoryResponseBuilder()
              ..name = name
              ..displayName = displayName)
            .build();

    test('H-1. maps name + displayName and drops blank-name entries', () {
      final options = MasterServiceMapper.fromApprovedCategoryList(
        <ApprovedCategoryResponse>[
          approvedDto(name: 'MANICURE', displayName: 'Манікюр'),
          approvedDto(name: 'NAIL_ART', displayName: 'Нейл-арт'),
          // Unusable: null name → dropped.
          approvedDto(name: null, displayName: 'Ghost'),
          // Unusable: empty name → dropped.
          approvedDto(name: '', displayName: 'Empty'),
        ],
      );

      expect(options.map((o) => o.name).toList(), <String>[
        'MANICURE',
        'NAIL_ART',
      ]);
      expect(options.first.displayName, 'Манікюр');
    });

    test('H-2. displayName falls back to name when absent', () {
      final options = MasterServiceMapper.fromApprovedCategoryList(
        <ApprovedCategoryResponse>[
          approvedDto(name: 'BROWS', displayName: null),
        ],
      );
      expect(options.single.displayName, 'BROWS');
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
