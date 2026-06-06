// Hand-authored contract-lock test for the mobile Phase 16.x service-types
// track. This guards the generated `api/` surface against a future
// `build_runner` / OpenAPI regeneration silently dropping or reverting the
// 16.x contract additions.
//
// THIS FILE IS NOT AUTO-GENERATED — it lives under test/contract/ so the
// codegen pipeline (which only writes test/*_test.dart stubs and lib/src/**)
// never overwrites it. Do not move it into the generated stub set.
//
// If any assertion here fails after a regen, the backend↔mobile service-types
// contract drifted; treat it as a real failure, not a stale test.

import 'package:built_value/serializer.dart';
import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

void main() {
  // standardSerializers applies StandardJsonPlugin, so models round-trip
  // through plain JSON maps (not built_value's flat key/value list). That is
  // the wire shape the Dio client actually sends/receives.
  final s = standardSerializers;

  Map<String, Object?> toJson<T>(Serializer<T> serializer, T value) {
    return s.serializeWith(serializer, value)! as Map<String, Object?>;
  }

  T fromJson<T>(Serializer<T> serializer, Map<String, Object?> json) {
    return s.deserializeWith(serializer, json)!;
  }

  group('SuggestServiceTypeRequest contract (backend 16.7 slug rename)', () {
    test('serializes a `categoryName` field and NEVER `categoryId`', () {
      final req = SuggestServiceTypeRequest(
        (b) => b
          ..name = 'Гель-лак'
          ..categoryName = 'NAILS'
          ..description = 'Покриття гель-лаком',
      );

      final json = toJson(SuggestServiceTypeRequest.serializer, req);

      // Highest-value assertion: the pre-16.7 UUID `categoryId` contract must
      // stay dead. A regen that reverts the spec would reintroduce it.
      expect(json.containsKey('categoryName'), isTrue,
          reason: 'categoryName wire field missing — 16.7 slug rename reverted');
      expect(json['categoryName'], 'NAILS');
      expect(json.containsKey('categoryId'), isFalse,
          reason: 'categoryId reappeared — pre-16.7 UUID contract resurrected');
    });

    test('round-trips through JSON preserving categoryName', () {
      final req = SuggestServiceTypeRequest(
        (b) => b
          ..name = 'Френч'
          ..categoryName = 'NAILS',
      );

      final back =
          fromJson(SuggestServiceTypeRequest.serializer, toJson(SuggestServiceTypeRequest.serializer, req));

      expect(back.categoryName, 'NAILS');
      expect(back.name, 'Френч');
    });
  });

  group('PlatformServiceTypeResponse contract (new 16.x lookup type)', () {
    test('round-trips id/slug/nameUk/categoryName', () {
      const json = <String, Object?>{
        'id': 'st-123',
        'slug': 'gel-polish',
        'nameUk': 'Гель-лак',
        'categoryName': 'NAILS',
      };

      final model = fromJson(PlatformServiceTypeResponse.serializer, json);

      expect(model.id, 'st-123');
      expect(model.slug, 'gel-polish');
      expect(model.nameUk, 'Гель-лак');
      expect(model.categoryName, 'NAILS');

      final reJson = toJson(PlatformServiceTypeResponse.serializer, model);
      expect(reJson['id'], 'st-123');
      expect(reJson['slug'], 'gel-polish');
      expect(reJson['nameUk'], 'Гель-лак');
      expect(reJson['categoryName'], 'NAILS');
    });
  });

  group('CreateServiceDefinitionRequest contract (nullable serviceTypeId)', () {
    test('serviceTypeId is carried when present', () {
      final req = CreateServiceDefinitionRequest(
        (b) => b
          ..name = 'Манікюр'
          ..category = 'NAILS'
          ..baseDurationMinutes = 60
          ..priceType = CreateServiceDefinitionRequestPriceTypeEnum.FIXED
          ..price = 500
          ..serviceTypeId = 'st-123',
      );

      final json = toJson(CreateServiceDefinitionRequest.serializer, req);

      expect(json['serviceTypeId'], 'st-123');
    });

    test('serviceTypeId null is accepted and omitted from wire payload', () {
      final req = CreateServiceDefinitionRequest(
        (b) => b
          ..name = 'Педикюр'
          ..category = 'NAILS'
          ..baseDurationMinutes = 90
          ..priceType = CreateServiceDefinitionRequestPriceTypeEnum.FIXED
          ..price = 700,
      );

      // Building without serviceTypeId must succeed (proves it is nullable,
      // i.e. the master may skip the optional service-type picker).
      final json = toJson(CreateServiceDefinitionRequest.serializer, req);

      expect(req.serviceTypeId, isNull);
      expect(json.containsKey('serviceTypeId'), isFalse,
          reason: 'null serviceTypeId should be omitted, not sent');
    });
  });

  group('MasterServiceResponse contract (nullable serviceTypeId + nameUk)', () {
    test('round-trips serviceTypeId and serviceTypeNameUk when present', () {
      const json = <String, Object?>{
        'id': 'ms-1',
        'masterId': 'master-1',
        'serviceTypeId': 'st-123',
        'serviceTypeNameUk': 'Гель-лак',
      };

      final model = fromJson(MasterServiceResponse.serializer, json);

      expect(model.serviceTypeId, 'st-123');
      expect(model.serviceTypeNameUk, 'Гель-лак');
    });

    test('accepts null serviceTypeId / serviceTypeNameUk (no type selected)', () {
      const json = <String, Object?>{
        'id': 'ms-2',
        'masterId': 'master-2',
      };

      final model = fromJson(MasterServiceResponse.serializer, json);

      expect(model.serviceTypeId, isNull);
      expect(model.serviceTypeNameUk, isNull);
    });
  });

  group('ServiceDefinitionResponse contract (nullable serviceTypeId + nameUk)', () {
    test('round-trips serviceTypeId and serviceTypeNameUk when present', () {
      const json = <String, Object?>{
        'id': 'sd-1',
        'name': 'Манікюр',
        'baseDurationMinutes': 60,
        'serviceTypeId': 'st-123',
        'serviceTypeNameUk': 'Гель-лак',
      };

      final model = fromJson(ServiceDefinitionResponse.serializer, json);

      expect(model.serviceTypeId, 'st-123');
      expect(model.serviceTypeNameUk, 'Гель-лак');
    });

    test('accepts null serviceTypeId / serviceTypeNameUk', () {
      const json = <String, Object?>{
        'id': 'sd-2',
        'name': 'Стрижка',
        'baseDurationMinutes': 45,
      };

      final model = fromJson(ServiceDefinitionResponse.serializer, json);

      expect(model.serviceTypeId, isNull);
      expect(model.serviceTypeNameUk, isNull);
    });
  });
}
