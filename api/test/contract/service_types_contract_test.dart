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

import 'package:built_collection/built_collection.dart';
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
          reason:
              'categoryName wire field missing — 16.7 slug rename reverted');
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

      final back = fromJson(SuggestServiceTypeRequest.serializer,
          toJson(SuggestServiceTypeRequest.serializer, req));

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

  group(
      'GET /service-types 200 contract '
      '(single-shape ApiResponseListPlatformServiceTypeResponse)', () {
    // REGRESSION LOCK — the original bug.
    //
    // The 200 response for /service-types was previously a 2-branch `oneOf`
    // (GetServiceTypes200Response) whose branches BOTH matched the real payload
    // `{id,slug,nameUk,categoryName}`. The `one_of` deserializer threw
    // `UnsupportedError("more than one match found")` on the real wire bytes →
    // fetchServiceTypes returned ServerFailure → the picker rendered EMPTY.
    //
    // The fix hid the legacy operation backend-side and regenerated the client
    // so the 200 is a SINGLE shape. These tests drive an actual JSON envelope
    // through the generated serializer exactly as the Dio client does. Under the
    // old ambiguous model this deserialize would have THROWN; under the
    // single-shape model it resolves to exactly one typed list.
    test(
        'deserializes a {success,data:[...],message,errors} envelope to a '
        'non-empty typed list with NO "more than one match found" throw', () {
      const json = <String, Object?>{
        'success': true,
        'data': <Object?>[
          <String, Object?>{
            'id': 'st-1',
            'slug': 'CLASSIC_LASHES',
            'nameUk': 'Класичне нарощування',
            'categoryName': 'EYELASH',
          },
          <String, Object?>{
            'id': 'st-2',
            'slug': 'VOLUME_LASHES',
            'nameUk': 'Об’ємне нарощування',
            'categoryName': 'EYELASH',
          },
        ],
        'message': null,
        'errors': null,
      };

      // returnsNormally is the load-bearing assertion: the old oneOf threw here.
      late ApiResponseListPlatformServiceTypeResponse envelope;
      expect(
        () => envelope = fromJson(
            ApiResponseListPlatformServiceTypeResponse.serializer, json),
        returnsNormally,
        reason: 'single-shape 200 must deserialize without an ambiguous '
            'oneOf "more than one match found" error',
      );

      expect(envelope.success, isTrue);
      expect(envelope.data, isNotNull);
      expect(envelope.data!.length, 2);
      expect(envelope.data!.first.id, 'st-1');
      expect(envelope.data!.first.slug, 'CLASSIC_LASHES');
      expect(envelope.data!.first.nameUk, 'Класичне нарощування');
      expect(envelope.data!.first.categoryName, 'EYELASH');
    });

    test('round-trips the envelope back to JSON preserving the data rows', () {
      final envelope = ApiResponseListPlatformServiceTypeResponse(
        (b) => b
          ..success = true
          ..data = ListBuilder<PlatformServiceTypeResponse>(
            <PlatformServiceTypeResponse>[
              PlatformServiceTypeResponse(
                (t) => t
                  ..id = 'st-9'
                  ..slug = 'FRENCH'
                  ..nameUk = 'Френч'
                  ..categoryName = 'NAILS',
              ),
            ],
          ),
      );

      final json = toJson(
          ApiResponseListPlatformServiceTypeResponse.serializer, envelope);

      expect(json['success'], isTrue);
      final data = json['data']! as List<Object?>;
      expect(data, hasLength(1));
      final row = data.first! as Map<String, Object?>;
      expect(row['slug'], 'FRENCH');
      expect(row['categoryName'], 'NAILS');
    });

    test('serializer registry no longer contains the legacy oneOf 200 wrapper',
        () {
      // The ambiguous GetServiceTypes200Response wrapper was deleted on regen.
      // If a future regen reintroduces a oneOf wrapper for this operation, its
      // serializer would be registered under that wireName and this guard fails.
      final hasLegacyWrapper = standardSerializers.serializers.any(
        (s) =>
            s.wireName == 'GetServiceTypes200Response' ||
            s.wireName == 'GetServiceTypesByPlatformCategory200Response',
      );
      expect(hasLegacyWrapper, isFalse,
          reason: 'an ambiguous oneOf 200 wrapper was reintroduced — the '
              'service-types load bug can recur');
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

    test('accepts null serviceTypeId / serviceTypeNameUk (no type selected)',
        () {
      const json = <String, Object?>{
        'id': 'ms-2',
        'masterId': 'master-2',
      };

      final model = fromJson(MasterServiceResponse.serializer, json);

      expect(model.serviceTypeId, isNull);
      expect(model.serviceTypeNameUk, isNull);
    });
  });

  group('ServiceDefinitionResponse contract (nullable serviceTypeId + nameUk)',
      () {
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
