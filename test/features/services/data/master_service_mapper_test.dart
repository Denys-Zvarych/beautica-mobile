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
//   G-ST-SET.  toUpdateRequest carries serviceTypeId when the patch sets one (M4).
//   G-ST-NULL. toUpdateRequest omits serviceTypeId when the patch leaves it null
//              (PATCH no-change — an unrelated edit never overwrites the type).
//   H-1.  fromApprovedCategoryList maps name+displayName and drops blank names.
//   I-1.  fromDto populates serviceDefId from serviceDefinition.id.
//   I-2.  fromServiceDefinitionDto carries the assignment id + maps base fields.
//   I-PRICE-FIXED.  fromDto maps FIXED pricing fields (priceType/priceMin/priceDisplay).
//   I-PRICE-RANGE.  fromDto maps RANGE pricing fields (priceType/priceMin/priceMax/priceDisplay).
//   I-SDR-PRICE.    fromServiceDefinitionDto maps RANGE pricing from ServiceDefinitionResponse.
//
//   ── Phase 16.3 — serviceTypeId create wiring + name pre-fill ──────────────
//   ST-CREATE-SET.    toCreateRequest sets serviceTypeId on the request when the
//                     input carries one.
//   ST-CREATE-NULL.   toCreateRequest leaves serviceTypeId null when the input's
//                     serviceTypeId is null (no regression to the existing create
//                     path — the generated serializer omits the null wire field).
//   ST-DTO-MSR.       fromDto reads serviceTypeId + serviceTypeNameUk from the
//                     top-level MSR envelope (V67+ precedence).
//   ST-DTO-FALLBACK.  fromDto falls back to the nested serviceDefinition for
//                     serviceTypeId + serviceTypeNameUk when the MSR envelope
//                     omits them.
//   ST-DTO-PRECEDENCE. fromDto prefers the MSR-envelope values over the nested
//                     serviceDefinition values when both are present.
//   ST-DTO-NULL.      fromDto carries null serviceTypeId/serviceTypeNameUk back
//                     when neither level supplies them.
//   ST-SDR-SET.       fromServiceDefinitionDto carries serviceTypeId +
//                     serviceTypeNameUk back from the definition response.
//   ST-SDR-NULL.      fromServiceDefinitionDto carries nulls when the definition
//                     response omits them.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
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
  String? serviceTypeId,
}) => MasterServiceCreate(
  name: 'Test',
  durationMinutes: 30,
  priceType: ServicePriceType.fixed,
  price: price,
  category: category,
  serviceTypeId: serviceTypeId,
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
  String? serviceTypeId,
  String? serviceTypeNameUk,
}) =>
    (ServiceDefinitionResponseBuilder()
          ..id = id
          ..name = name
          ..baseDurationMinutes = baseDurationMinutes
          ..priceType = priceType
          ..priceMin = priceMin
          ..priceMax = priceMax
          ..priceDisplay = priceDisplay ?? '${priceMin.toInt()} грн'
          ..serviceTypeId = serviceTypeId
          ..serviceTypeNameUk = serviceTypeNameUk
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

    // ── Item 3 (M4) — serviceTypeId on the PATCH wire ─────────────────────
    // Guards the silent-drop bug: a non-null serviceTypeId MUST reach the
    // generated request; a null serviceTypeId MUST be omitted (PATCH "no
    // change"), so a save that does not touch the type never overwrites it.

    test(
      'G-ST-SET. toUpdateRequest carries serviceTypeId when the patch sets one',
      () {
        final request = MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(serviceTypeId: 'type-new'),
        );
        expect(
          request.serviceTypeId,
          equals('type-new'),
          reason:
              'a non-null serviceTypeId must reach the wire request (M4 — '
              'guards the silent-drop regression)',
        );
      },
    );

    test(
      'G-ST-NULL. toUpdateRequest omits serviceTypeId when the patch leaves it '
      'null (PATCH no-change)',
      () {
        final request = MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(name: 'Інша назва'),
        );
        expect(
          request.serviceTypeId,
          isNull,
          reason:
              'a null serviceTypeId must be omitted so an unrelated edit never '
              'overwrites the current service type',
        );
      },
    );

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

    // ── G-PARTIAL. Partial-update non-null guarantee (mobile-qa LOW) ─────────
    // PATCH semantics: a MasterServiceUpdate that sets only a SUBSET of fields
    // must produce a request that carries EXACTLY those fields and leaves every
    // unset field null on the builder — the generated serializer then omits the
    // null keys, so the backend treats absent keys as "no change". This is the
    // single combined assertion the per-field G-tests above don't make: set a
    // few fields, leave the rest null, and prove the present set equals the
    // touched set with no leakage into untouched fields.

    test('G-PARTIAL. toUpdateRequest carries only the non-null fields — '
        'untouched fields stay null on the request', () {
      // Touch exactly three fields (name, durationMinutes, category); leave
      // everything else — description, serviceTypeId, buffer, and the whole
      // price block — null.
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(
          name: 'Оновлена назва',
          durationMinutes: 50,
          category: 'HAIRCUT',
        ),
      );

      // Present — exactly the three fields the patch set.
      expect(request.name, equals('Оновлена назва'));
      expect(request.baseDurationMinutes, equals(50));
      expect(request.category, equals('HAIRCUT'));

      // Absent — every field the patch did NOT touch must be null so the
      // serializer drops it from the PATCH body (no accidental overwrite).
      expect(
        request.description,
        isNull,
        reason: 'description was not in the patch — must stay null',
      );
      expect(
        request.serviceTypeId,
        isNull,
        reason: 'serviceTypeId was not in the patch — must stay null',
      );
      expect(
        request.bufferMinutesAfter,
        isNull,
        reason: 'bufferMinutesAfter was not in the patch — must stay null',
      );
      expect(
        request.priceType,
        isNull,
        reason: 'no price field in the patch — price block must be absent',
      );
      expect(request.price, isNull);
      expect(request.priceMin, isNull);
      expect(request.priceMax, isNull);
    });

    test('G-PARTIAL-PRICE-ONLY. a price-only patch carries the price block and '
        'leaves all non-price fields null', () {
      // The complementary subset: touch ONLY the FIXED price block. name,
      // category, duration, buffer, serviceTypeId must all stay null.
      final request = MasterServiceMapper.toUpdateRequest(
        const MasterServiceUpdate(
          priceType: ServicePriceType.fixed,
          price: 650.0,
        ),
      );

      expect(
        request.priceType,
        UpdateServiceDefinitionRequestPriceTypeEnum.FIXED,
      );
      expect(request.price, equals(650.0));

      expect(request.name, isNull);
      expect(request.category, isNull);
      expect(request.baseDurationMinutes, isNull);
      expect(request.bufferMinutesAfter, isNull);
      expect(request.serviceTypeId, isNull);
      // RANGE-only fields must remain null in FIXED mode.
      expect(request.priceMin, isNull);
      expect(request.priceMax, isNull);
    });

    // ── G-ERR. toUpdateRequest error branches (mobile-qa LOW) ────────────────
    // Each branch below feeds an invalid value into a field the patch DOES set
    // and asserts the mapper throws ArgumentError at the data boundary (before
    // the request reaches the network layer). These guard the fail-fast
    // validation in toUpdateRequest that the existing B4 tests only partially
    // cover (B4 hit FIXED price:0 and the inverted RANGE; these add the
    // duration, buffer, and the null/zero-floor branches).

    test('G-ERR-DURATION. durationMinutes:0 throws ArgumentError', () {
      expect(
        () => MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(durationMinutes: 0),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'durationMinutes'),
        ),
        reason: 'durationMinutes must be >= 1 when present',
      );
    });

    test('G-ERR-BUFFER. negative bufferMinutesAfter throws ArgumentError', () {
      expect(
        () => MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(bufferMinutesAfter: -5),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'bufferMinutesAfter',
          ),
        ),
        reason: 'bufferMinutesAfter must be >= 0 when present',
      );
    });

    test(
      'G-ERR-FIXED-NULL. FIXED priceType with null price throws ArgumentError',
      () {
        // priceType present (so the price block is validated) but price omitted
        // — the mapper must reject it rather than emit a FIXED body with no
        // amount. Complements B4-FIXED-ZERO (price:0) with the null case.
        expect(
          () => MasterServiceMapper.toUpdateRequest(
            const MasterServiceUpdate(priceType: ServicePriceType.fixed),
          ),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'price')),
          reason: 'FIXED mode requires a non-null price > 0',
        );
      },
    );

    test('G-ERR-RANGE-MIN-ZERO. RANGE priceType with priceMin:0 throws '
        'ArgumentError', () {
      expect(
        () => MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(
            priceType: ServicePriceType.range,
            priceMin: 0,
            priceMax: 500.0,
          ),
        ),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'priceMin')),
        reason: 'RANGE mode requires priceMin > 0',
      );
    });

    test('G-ERR-RANGE-MAX-NULL. RANGE priceType with null priceMax throws '
        'ArgumentError', () {
      // priceMin valid but priceMax omitted — the RANGE invariant
      // (priceMax > priceMin) cannot hold with a null ceiling, so the mapper
      // must reject. Complements B4-RANGE-INVERTED (max <= min) with the
      // null-ceiling case.
      expect(
        () => MasterServiceMapper.toUpdateRequest(
          const MasterServiceUpdate(
            priceType: ServicePriceType.range,
            priceMin: 400.0,
          ),
        ),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'priceMax')),
        reason: 'RANGE mode requires a non-null priceMax > priceMin',
      );
    });
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

  // ── J. fromDto broken-contract guard (log-hygiene regression) ─────────────
  //
  // Security-backlog: the broken-contract log in fromDto is now kDebugMode-
  // gated and no longer interpolates raw values. These tests pin the OBSERVABLE
  // behaviour — that a missing/blank assignment id still throws the same
  // ServerFailure(statusCode: null) — so the log-hygiene refactor cannot
  // silently turn the guard into a no-op. We assert the failure, never any log
  // text.
  group('J. fromDto broken-contract guard', () {
    test('J-1. null id throws ServerFailure(statusCode: null)', () {
      final dto =
          (MasterServiceResponseBuilder()
                // id intentionally left unset (null on the builder)
                ..serviceDefinition.replace(buildDef(id: 'def-x'))
                ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                ..priceMin = 500
                ..priceDisplay = '500 грн'
                ..isActive = true)
              .build();

      expect(
        () => MasterServiceMapper.fromDto(dto),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', null),
        ),
      );
    });

    test('J-2. empty-string id throws ServerFailure(statusCode: null)', () {
      final dto =
          (MasterServiceResponseBuilder()
                ..id = ''
                ..serviceDefinition.replace(buildDef(id: 'def-x'))
                ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                ..priceMin = 500
                ..priceDisplay = '500 грн'
                ..isActive = true)
              .build();

      expect(
        () => MasterServiceMapper.fromDto(dto),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  // ── ST. Phase 16.3 — serviceTypeId create wiring + response round-trip ────

  group('ST. toCreateRequest — serviceTypeId wiring', () {
    test('ST-CREATE-SET. sets serviceTypeId when the input carries one', () {
      final request = MasterServiceMapper.toCreateRequest(
        _createFixed(serviceTypeId: 'type-abc'),
      );
      expect(
        request.serviceTypeId,
        equals('type-abc'),
        reason: 'a selected service type must reach the create request',
      );
    });

    test('ST-CREATE-NULL. leaves serviceTypeId null when input is null', () {
      // The master skipped the (optional) picker. The generated serializer
      // omits null builder fields, so this is the "omitted from the wire body"
      // case — and proves the existing no-type create path is unchanged.
      final request = MasterServiceMapper.toCreateRequest(_createFixed());
      expect(
        request.serviceTypeId,
        isNull,
        reason:
            'no service type selected → serviceTypeId must stay null on the '
            'request (omitted from the wire body — no regression)',
      );
      // Sanity: the rest of the request is still well-formed.
      expect(request.name, equals('Test'));
      expect(
        request.priceType,
        CreateServiceDefinitionRequestPriceTypeEnum.FIXED,
      );
      expect(request.price, equals(500.0));
    });
  });

  group('ST. response round-trip — serviceTypeId + serviceTypeNameUk', () {
    test(
      'ST-DTO-MSR. fromDto reads service type from the top-level MSR envelope',
      () {
        final dto =
            (MasterServiceResponseBuilder()
                  ..id = 'a-st-msr'
                  ..serviceDefinition.replace(buildDef(id: 'def-st-msr'))
                  ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                  ..priceMin = 500
                  ..priceDisplay = '500 грн'
                  ..serviceTypeId = 'type-msr'
                  ..serviceTypeNameUk = 'Класичний манікюр'
                  ..isActive = true)
                .build();

        final service = MasterServiceMapper.fromDto(dto);

        expect(service.serviceTypeId, equals('type-msr'));
        expect(service.serviceTypeNameUk, equals('Класичний манікюр'));
      },
    );

    test(
      'ST-DTO-FALLBACK. fromDto falls back to nested serviceDefinition when the '
      'MSR envelope omits the service type',
      () {
        final dto =
            (MasterServiceResponseBuilder()
                  ..id = 'a-st-fb'
                  ..serviceDefinition.replace(
                    buildDef(
                      id: 'def-st-fb',
                      serviceTypeId: 'type-nested',
                      serviceTypeNameUk: 'Педикюр',
                    ),
                  )
                  ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                  ..priceMin = 500
                  ..priceDisplay = '500 грн'
                  // serviceTypeId / serviceTypeNameUk intentionally unset on MSR
                  ..isActive = true)
                .build();

        final service = MasterServiceMapper.fromDto(dto);

        expect(service.serviceTypeId, equals('type-nested'));
        expect(service.serviceTypeNameUk, equals('Педикюр'));
      },
    );

    test('ST-DTO-PRECEDENCE. fromDto prefers the MSR envelope over the nested '
        'definition when both supply a service type', () {
      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'a-st-prec'
                ..serviceDefinition.replace(
                  buildDef(
                    id: 'def-st-prec',
                    serviceTypeId: 'type-nested',
                    serviceTypeNameUk: 'Nested name',
                  ),
                )
                ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                ..priceMin = 500
                ..priceDisplay = '500 грн'
                ..serviceTypeId = 'type-envelope'
                ..serviceTypeNameUk = 'Envelope name'
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      expect(
        service.serviceTypeId,
        equals('type-envelope'),
        reason: 'MSR-envelope-first precedence (dto.serviceTypeId ?? def…)',
      );
      expect(service.serviceTypeNameUk, equals('Envelope name'));
    });

    test(
      'ST-DTO-NULL. fromDto carries null when neither level supplies a type',
      () {
        final dto =
            (MasterServiceResponseBuilder()
                  ..id = 'a-st-null'
                  ..serviceDefinition.replace(buildDef(id: 'def-st-null'))
                  ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                  ..priceMin = 500
                  ..priceDisplay = '500 грн'
                  ..isActive = true)
                .build();

        final service = MasterServiceMapper.fromDto(dto);

        expect(service.serviceTypeId, isNull);
        expect(service.serviceTypeNameUk, isNull);
      },
    );

    test('ST-SDR-SET. fromServiceDefinitionDto carries service type back', () {
      final def = buildDef(
        id: 'def-st-sdr',
        serviceTypeId: 'type-sdr',
        serviceTypeNameUk: 'Стрижка',
      );

      final service = MasterServiceMapper.fromServiceDefinitionDto(
        def,
        assignmentId: 'assign-st-sdr',
      );

      expect(service.serviceTypeId, equals('type-sdr'));
      expect(service.serviceTypeNameUk, equals('Стрижка'));
    });

    test('ST-SDR-NULL. fromServiceDefinitionDto carries null when omitted', () {
      final def = buildDef(id: 'def-st-sdr-null');

      final service = MasterServiceMapper.fromServiceDefinitionDto(
        def,
        assignmentId: 'assign-st-sdr-null',
      );

      expect(service.serviceTypeId, isNull);
      expect(service.serviceTypeNameUk, isNull);
    });
  });

  // ── ND. Regression guard — the service "draft" concept is GONE ────────────
  //
  // Backend V80 removed the draft flag (`isDraft`) from MasterServiceResponse
  // and ServiceDefinitionResponse. The mobile app's draft affordance — the
  // domain `isDraft` field, the draft badge, the "set price" CTA, and the
  // draft card variant — were all deleted (user-approved clean removal). The
  // deleted file `services_list_draft_card_test.dart` is intentionally gone and
  // must NOT be recreated.
  //
  // These tests are the data-layer half of that guard. They assert that a
  // realistic DTO maps to a plain, fully-priced, ACTIVE [MasterService] with no
  // residual draft state. The omission of `isDraft` from [MasterService] is
  // type-enforced — re-introducing the field (or any draft inference from a
  // zero price) would either fail to compile here or flip one of these
  // assertions, blocking the merge before it can reach a broken APK build.
  group('ND. no draft affordance — mapper produces plain active services', () {
    test('ND-1. fromDto maps a realistic MSR to a plain active service — no '
        'draft state, full price + duration meta', () {
      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'assignment-nd'
                ..serviceDefinition.replace(
                  buildDef(
                    id: 'def-nd',
                    name: 'Стрижка',
                    baseDurationMinutes: 45,
                    priceType: ServiceDefinitionResponsePriceTypeEnum.FIXED,
                    priceMin: 750,
                    priceDisplay: '750 грн',
                  ),
                )
                ..priceType = MasterServiceResponsePriceTypeEnum.FIXED
                ..priceMin = 750
                ..priceDisplay = '750 грн'
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      // The service is bookable (active), fully priced, and time-bounded — the
      // exact opposite of a "draft awaiting a price".
      expect(service.isActive, isTrue);
      expect(service.priceDisplay, equals('750 грн'));
      expect(service.priceMin, equals(750.0));
      expect(service.durationMinutes, equals(45));

      // A zero/absent price must NOT be re-interpreted as a draft signal, and
      // [MasterService] must expose no draft member. freezed's generated
      // toString() enumerates every field of the value object, so asserting it
      // never mentions "draft" is a real text-level guard: re-adding an
      // `isDraft` (or any `draft*`) field to the model flips this red.
      expect(
        service.toString().toLowerCase(),
        isNot(contains('draft')),
        reason:
            'MasterService must carry no draft field — re-introducing isDraft '
            'would surface in freezed toString() and fail this guard (V80 '
            'removed the draft concept; the draft affordance was deleted)',
      );
    });

    test('ND-2. a zero-floor RANGE service still maps to an active service — '
        'no draft inference from a missing/zero price', () {
      // Even if pricing data is incomplete, the mapper must never synthesise a
      // draft state. The service stays active and renders whatever priceDisplay
      // the backend supplied — there is no "set price" pathway anymore.
      final dto =
          (MasterServiceResponseBuilder()
                ..id = 'assignment-nd-zero'
                ..serviceDefinition.replace(
                  buildDef(
                    id: 'def-nd-zero',
                    priceType: ServiceDefinitionResponsePriceTypeEnum.RANGE,
                    priceMin: 0,
                    priceMax: 500,
                    priceDisplay: 'до 500 грн',
                  ),
                )
                ..priceType = MasterServiceResponsePriceTypeEnum.RANGE
                ..priceMin = 0
                ..priceMax = 500
                ..priceDisplay = 'до 500 грн'
                ..isActive = true)
              .build();

      final service = MasterServiceMapper.fromDto(dto);

      expect(service.isActive, isTrue);
      expect(service.priceType, ServicePriceType.range);
      expect(service.priceMin, equals(0.0));
      expect(service.priceMax, equals(500.0));
      expect(service.priceDisplay, equals('до 500 грн'));
    });
  });
}
