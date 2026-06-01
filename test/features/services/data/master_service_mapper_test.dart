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
//   G-1.  toUpdateRequest sets category when category is provided.
//   G-2.  toUpdateRequest leaves category null when omitted (PATCH semantics).
//   G-3.  toUpdateRequest maps durationMinutes/price → baseDurationMinutes/basePrice.
//   H-1.  fromApprovedCategoryList maps name+displayName and drops blank names.
//   I-1.  fromDto populates serviceDefId from serviceDefinition.id.
//   I-2.  fromServiceDefinitionDto carries the assignment id + maps base fields.

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

  // ── G. toUpdateRequest — generated UpdateServiceDefinitionRequest ─────────

  group('G. toUpdateRequest — UpdateServiceDefinitionRequest fields', () {
    // G-1: category present in patch → request.category is set.
    test('G-1. sets category when category is provided', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(category: 'MAKEUP'),
      );
      expect(
        request.category,
        equals('MAKEUP'),
        reason: 'request.category must equal the provided wire name string',
      );
    });

    // G-2: no category in patch → request.category stays null (omitted on wire).
    test('G-2. leaves category null when omitted (PATCH semantics)', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(name: 'Тест'),
      );
      expect(
        request.category,
        isNull,
        reason:
            'request.category must be null when omitted — the generated '
            'serializer skips null fields so the backend treats it as no-change',
      );
      expect(request.name, equals('Тест'));
    });

    // G-3: domain durationMinutes/price map to wire baseDurationMinutes/basePrice.
    test('G-3. maps durationMinutes/price → baseDurationMinutes/basePrice', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(durationMinutes: 75, price: 600.0),
      );
      expect(request.baseDurationMinutes, equals(75));
      expect(request.basePrice, equals(600.0));
    });
  });

  // ── I. serviceDefId plumbing ──────────────────────────────────────────────

  group('I. serviceDefId plumbing', () {
    ServiceDefinitionResponse buildDef({
      String id = 'def-001',
      String name = 'Манікюр',
      int baseDurationMinutes = 60,
      num basePrice = 500,
    }) =>
        (ServiceDefinitionResponseBuilder()
              ..id = id
              ..name = name
              ..baseDurationMinutes = baseDurationMinutes
              ..basePrice = basePrice
              ..isActive = true)
            .build();

    // I-1: fromDto reads serviceDefinition.id into MasterService.serviceDefId.
    test('I-1. fromDto populates serviceDefId from serviceDefinition.id', () {
      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'assignment-xyz'
                ..serviceDefinition.replace(buildDef(id: 'def-777'))
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      expect(
        service.id,
        equals('assignment-xyz'),
        reason: 'id must remain the assignment UUID',
      );
      expect(
        service.serviceDefId,
        equals('def-777'),
        reason: 'serviceDefId must come from serviceDefinition.id',
      );
    });

    // I-2: fromServiceDefinitionDto carries the passed assignment id through and
    //      maps the definition base fields.
    test(
      'I-2. fromServiceDefinitionDto carries assignmentId + base fields',
      () {
        final def = buildDef(
          id: 'def-888',
          name: 'Манікюр Оновлений',
          baseDurationMinutes: 75,
          basePrice: 600,
        );

        final service = MasterServiceMapper.fromServiceDefinitionDto(
          def,
          assignmentId: 'assignment-abc',
        );

        expect(
          service.id,
          equals('assignment-abc'),
          reason: 'assignment id is threaded through (response omits it)',
        );
        expect(service.serviceDefId, equals('def-888'));
        expect(service.name, equals('Манікюр Оновлений'));
        expect(service.durationMinutes, equals(75));
        expect(service.price, equals(600.0));
      },
    );
  });
}
