// Tests for [MasterServiceMapper].
//
// Strategy: pure Dart unit tests — no widget tree, no Riverpod container,
// no HTTP mocks required. [MasterServiceMapper] is a static-method-only
// abstract final class.
//
// Coverage:
//   F-1 through F-7.  toCreateRequest passes each wire name through as a plain
//                     String on request.category (enum→String backend change).
//   F-8.  category: null  → ArgumentError.
//   F-9.  arbitrary wire  → passed through verbatim.
//   F-FIXED.  FIXED mode: sets priceType=FIXED + price; priceMin/Max absent.
//   F-RANGE.  RANGE mode: sets priceType=RANGE + priceMin + priceMax; price absent.
//   F-FIXED-INVALID. FIXED price <= 0 → ArgumentError.
//   F-RANGE-INVALID. RANGE priceMax <= priceMin → ArgumentError.
//   G-1.  toUpdateRequest sets category when category is provided.
//   G-2.  toUpdateRequest leaves category null when omitted (PATCH semantics).
//   G-3.  toUpdateRequest maps durationMinutes → baseDurationMinutes.
//   G-FIXED. toUpdateRequest sets priceType=FIXED + price for FIXED update.
//   G-RANGE. toUpdateRequest sets priceType=RANGE + priceMin + priceMax for RANGE update.
//   G-NO-PRICE. toUpdateRequest omits price block when all price fields are null.
//   H-1.  fromApprovedCategoryList maps name+displayName and drops blank names.
//   I-1.  fromDto populates serviceDefId from serviceDefinition.id.
//   I-2.  fromServiceDefinitionDto carries the assignment id + maps base fields.
//   I-PRICE-FIXED.  fromDto maps FIXED pricing fields (priceType/priceMin/priceDisplay).
//   I-PRICE-RANGE.  fromDto maps RANGE pricing fields (priceType/priceMin/priceMax/priceDisplay).
//   I-SDR-PRICE.    fromServiceDefinitionDto maps RANGE pricing from ServiceDefinitionResponse.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/services/data/master_service_mapper.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a minimal FIXED [MasterServiceCreate].
MasterServiceCreate _createFixed({
  String? category = 'MANICURE',
  double price = 500.0,
}) => MasterServiceCreate(
  name: 'Test',
  durationMinutes: 30,
  priceType: ServicePriceType.fixed,
  price: price,
  category: category,
);

/// Builds a minimal RANGE [MasterServiceCreate].
MasterServiceCreate _createRange({
  double priceMin = 400.0,
  double priceMax = 700.0,
}) => MasterServiceCreate(
  name: 'Test',
  durationMinutes: 30,
  priceType: ServicePriceType.range,
  priceMin: priceMin,
  priceMax: priceMax,
  category: 'MANICURE',
);

/// Builds a minimal [ServiceDefinitionResponse] with pricing fields.
ServiceDefinitionResponse buildDef({
  String id = 'def-001',
  String name = 'Манікюр',
  int baseDurationMinutes = 60,
  ServiceDefinitionResponsePriceTypeEnum priceType =
      ServiceDefinitionResponsePriceTypeEnum.FIXED,
  num priceMin = 500,
  num? priceMax,
  String? priceDisplay,
}) =>
    (ServiceDefinitionResponseBuilder()
          ..id = id
          ..name = name
          ..baseDurationMinutes = baseDurationMinutes
          ..priceType = priceType
          ..priceMin = priceMin
          ..priceMax = priceMax
          ..priceDisplay = priceDisplay ?? '${priceMin.toInt()} грн'
          ..isActive = true)
        .build();

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  // ── F. category String pass-through via toCreateRequest ───────────────────

  group('F. toCreateRequest — category String pass-through', () {
    const wireNames = <String>[
      'MANICURE',
      'PEDICURE',
      'EYELASH',
      'HAIRCUT',
      'MAKEUP',
      'BROWS',
      'OTHER',
      'NAIL_ART',
    ];

    for (final wire in wireNames) {
      test('wire "$wire" is forwarded verbatim as a String', () {
        final request = MasterServiceMapper.toCreateRequest(
          _createFixed(category: wire),
        );
        expect(
          request.category,
          equals(wire),
          reason: 'category must be sent as the plain wire String "$wire"',
        );
      });
    }

    test('F-8. null category throws ArgumentError (category is required)', () {
      expect(
        () => MasterServiceMapper.toCreateRequest(_createFixed(category: null)),
        throwsArgumentError,
        reason: 'category is @NotBlank on the backend — mapper must fail fast',
      );
    });

    test('F-9. arbitrary wire name passes through unchanged', () {
      final request = MasterServiceMapper.toCreateRequest(
        _createFixed(category: 'SOME_NEW_CATEGORY'),
      );
      expect(request.category, equals('SOME_NEW_CATEGORY'));
    });
  });

  // ── F-FIXED / F-RANGE. toCreateRequest — pricing modes ───────────────────

  group('F-FIXED/RANGE. toCreateRequest — pricing mode fields', () {
    test('F-FIXED. FIXED mode sends priceType=FIXED and price', () {
      final request = MasterServiceMapper.toCreateRequest(
        _createFixed(price: 750.0),
      );
      expect(
        request.priceType,
        CreateServiceDefinitionRequestPriceTypeEnum.FIXED,
      );
      expect(request.price, equals(750.0));
      expect(request.priceMin, isNull);
      expect(request.priceMax, isNull);
    });

    test('F-RANGE. RANGE mode sends priceType=RANGE, priceMin, priceMax', () {
      final request = MasterServiceMapper.toCreateRequest(
        _createRange(priceMin: 400.0, priceMax: 800.0),
      );
      expect(
        request.priceType,
        CreateServiceDefinitionRequestPriceTypeEnum.RANGE,
      );
      expect(request.priceMin, equals(400.0));
      expect(request.priceMax, equals(800.0));
      expect(request.price, isNull);
    });

    test('F-FIXED-INVALID. FIXED price <= 0 throws ArgumentError', () {
      expect(
        () => MasterServiceMapper.toCreateRequest(
          const MasterServiceCreate(
            name: 'x',
            durationMinutes: 30,
            priceType: ServicePriceType.fixed,
            price: 0,
            category: 'MANICURE',
          ),
        ),
        throwsArgumentError,
        reason: 'price must be > 0 for FIXED mode',
      );
    });

    test('F-RANGE-INVALID. priceMax <= priceMin throws ArgumentError', () {
      expect(
        () => MasterServiceMapper.toCreateRequest(
          _createRange(priceMin: 800.0, priceMax: 500.0),
        ),
        throwsArgumentError,
        reason: 'priceMax must be strictly greater than priceMin',
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
          approvedDto(name: null, displayName: 'Ghost'),
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
    test('G-1. sets category when category is provided', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(category: 'MAKEUP'),
      );
      expect(request.category, equals('MAKEUP'));
    });

    test('G-2. leaves category null when omitted (PATCH semantics)', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(name: 'Тест'),
      );
      expect(request.category, isNull);
      expect(request.name, equals('Тест'));
    });

    test('G-3. maps durationMinutes → baseDurationMinutes', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(durationMinutes: 75),
      );
      expect(request.baseDurationMinutes, equals(75));
    });

    test('G-FIXED. FIXED update sends priceType=FIXED and price', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(
          priceType: ServicePriceType.fixed,
          price: 600.0,
        ),
      );
      expect(
        request.priceType,
        UpdateServiceDefinitionRequestPriceTypeEnum.FIXED,
      );
      expect(request.price, equals(600.0));
      expect(request.priceMin, isNull);
      expect(request.priceMax, isNull);
    });

    test(
      'G-RANGE. RANGE update sends priceType=RANGE + priceMin + priceMax',
      () {
        final request = MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(
            priceType: ServicePriceType.range,
            priceMin: 500.0,
            priceMax: 900.0,
          ),
        );
        expect(
          request.priceType,
          UpdateServiceDefinitionRequestPriceTypeEnum.RANGE,
        );
        expect(request.priceMin, equals(500.0));
        expect(request.priceMax, equals(900.0));
        expect(request.price, isNull);
      },
    );

    test('G-NO-PRICE. omits price block when all price fields are null', () {
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(name: 'Нове ім\'я'),
      );
      expect(
        request.priceType,
        isNull,
        reason: 'priceType must be null when price block is absent',
      );
      expect(request.price, isNull);
      expect(request.priceMin, isNull);
      expect(request.priceMax, isNull);
    });

    // B4 (MEDIUM) — toUpdateRequest invalid-price fail-fasts ─────────────────

    test('B4-FIXED-ZERO. FIXED update with price:0 throws ArgumentError', () {
      expect(
        () => MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(
            priceType: ServicePriceType.fixed,
            price: 0,
          ),
        ),
        throwsArgumentError,
        reason: 'FIXED mode requires price > 0 — price:0 must be rejected',
      );
    });

    test(
      'B4-RANGE-INVERTED. RANGE update with priceMin:900 priceMax:500 throws '
      'ArgumentError',
      () {
        expect(
          () => MasterServiceMapper.toUpdateRequest(
            const MasterServiceUpdate(
              priceType: ServicePriceType.range,
              priceMin: 900.0,
              priceMax: 500.0,
            ),
          ),
          throwsArgumentError,
          reason:
              'RANGE mode requires priceMax > priceMin — '
              'priceMin:900 priceMax:500 must be rejected',
        );
      },
    );
  });

  // ── I. serviceDefId plumbing + pricing ────────────────────────────────────

  group('I. serviceDefId plumbing + pricing fields', () {
    test('I-1. fromDto populates serviceDefId from serviceDefinition.id', () {
      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'assignment-xyz'
                ..serviceDefinition.replace(buildDef(id: 'def-777'))
                ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                ..priceMin = 500
                ..priceDisplay = '500 грн'
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      expect(service.id, equals('assignment-xyz'));
      expect(service.serviceDefId, equals('def-777'));
    });

    test('I-PRICE-FIXED. fromDto maps FIXED pricing correctly', () {
      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'a-001'
                ..serviceDefinition.replace(
                  buildDef(
                    id: 'def-001',
                    priceType: ServiceDefinitionResponsePriceTypeEnum.FIXED,
                    priceMin: 750,
                    priceDisplay: '750 грн',
                  ),
                )
                ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                ..priceMin = 750
                ..priceMax = null
                ..priceDisplay = '750 грн'
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      expect(service.priceType, ServicePriceType.fixed);
      expect(service.priceMin, equals(750.0));
      expect(service.priceMax, isNull);
      expect(service.priceDisplay, equals('750 грн'));
    });

    test('I-PRICE-RANGE. fromDto maps RANGE pricing correctly', () {
      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'a-002'
                ..serviceDefinition.replace(
                  buildDef(
                    id: 'def-002',
                    priceType: ServiceDefinitionResponsePriceTypeEnum.RANGE,
                    priceMin: 500,
                    priceMax: 800,
                    priceDisplay: 'від 500 до 800 грн',
                  ),
                )
                ..priceType = MasterServiceResponsePriceTypeEnum.RANGE
                ..priceMin = 500
                ..priceMax = 800
                ..priceDisplay = 'від 500 до 800 грн'
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      expect(service.priceType, ServicePriceType.range);
      expect(service.priceMin, equals(500.0));
      expect(service.priceMax, equals(800.0));
      expect(service.priceDisplay, equals('від 500 до 800 грн'));
    });

    test(
      'I-2. fromServiceDefinitionDto carries assignmentId + base fields',
      () {
        final def = buildDef(
          id: 'def-888',
          name: 'Манікюр Оновлений',
          baseDurationMinutes: 75,
          priceMin: 600,
          priceDisplay: '600 грн',
        );

        final service = MasterServiceMapper.fromServiceDefinitionDto(
          def,
          assignmentId: 'assignment-abc',
        );

        expect(service.id, equals('assignment-abc'));
        expect(service.serviceDefId, equals('def-888'));
        expect(service.name, equals('Манікюр Оновлений'));
        expect(service.durationMinutes, equals(75));
        expect(service.priceMin, equals(600.0));
      },
    );

    test('I-SDR-PRICE. fromServiceDefinitionDto maps RANGE pricing', () {
      final def = buildDef(
        id: 'def-999',
        priceType: ServiceDefinitionResponsePriceTypeEnum.RANGE,
        priceMin: 400,
        priceMax: 700,
        priceDisplay: 'від 400 до 700 грн',
      );

      final service = MasterServiceMapper.fromServiceDefinitionDto(
        def,
        assignmentId: 'assign-001',
      );

      expect(service.priceType, ServicePriceType.range);
      expect(service.priceMin, equals(400.0));
      expect(service.priceMax, equals(700.0));
      expect(service.priceDisplay, equals('від 400 до 700 грн'));
    });

    // B5 (MEDIUM) — fromDto fail-safes for null priceType + null priceDisplay ─

    test(
      'B5-NULL-PRICE-TYPE. null priceType on MasterServiceResponse defaults to '
      'ServicePriceType.fixed',
      () {
        // Build a DTO with no priceType set at the top level and a FIXED nested
        // serviceDefinition (the default from buildDef). The mapper must fall
        // back to FIXED rather than throw.
        final dto =
            (MasterServiceResponseBuilder()
                  ..id = 'a-null-pt'
                  ..serviceDefinition.replace(
                    buildDef(
                      id: 'def-null-pt',
                      priceType: ServiceDefinitionResponsePriceTypeEnum.FIXED,
                      priceMin: 300,
                    ),
                  )
                  // priceType is intentionally left unset (null on the builder)
                  ..priceMin = 300
                  ..priceDisplay = '300 грн'
                  ..isActive = true)
                .build();

        final service = MasterServiceMapper.fromDto(dto);

        expect(
          service.priceType,
          ServicePriceType.fixed,
          reason:
              'a null priceType on MasterServiceResponse must default to '
              'ServicePriceType.fixed (safe fallback)',
        );
      },
    );

    test('B5-NULL-PRICE-DISPLAY. null priceDisplay on both MSR and nested def '
        'resolves to empty string', () {
      // Build a DTO where priceDisplay is left unset at both levels.
      // We override buildDef's default by constructing manually so priceDisplay
      // is genuinely null (not the generated default '300 грн').
      final def =
          (ServiceDefinitionResponseBuilder()
                ..id = 'def-null-pd'
                ..name = 'Тест'
                ..baseDurationMinutes = 30
                ..priceType = ServiceDefinitionResponsePriceTypeEnum.FIXED
                ..priceMin = 200
                // priceDisplay intentionally left unset (null)
                ..isActive = true)
              .build();

      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'a-null-pd'
                ..serviceDefinition.replace(def)
                ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                ..priceMin = 200
                // priceDisplay intentionally left unset (null)
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      expect(
        service.priceDisplay,
        equals(''),
        reason:
            'a null priceDisplay on both MSR and nested def must resolve to '
            "an empty string (the mapper's '' last-resort default)",
      );
    });
  });
}
