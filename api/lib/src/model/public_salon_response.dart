//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'public_salon_response.g.dart';

/// PublicSalonResponse
///
/// Properties:
/// * [id]
/// * [name]
/// * [description]
/// * [city]
/// * [region]
/// * [address]
/// * [cityId] - Taxonomy city. Every salon has one — salons.city_id is DB-level NOT NULL (V150/V151) and application-enforced from Phase 10.6 (LocalityWriteValidator). Never null on the wire.
/// * [oblastId] - Parent oblast of cityId, resolved at read time (see #from). cities.oblast_id is itself DB-level NOT NULL with a FK to oblasts, and cityId is guaranteed non-null and FK-valid, so resolution always succeeds. Never null on the wire.
/// * [districtId]
/// * [street]
/// * [buildingNo]
/// * [locationNote]
/// * [phone] - Salon's public business contact number. Intentionally exposed on this permitAll path: it is the contact clients are meant to call, the same value already returned by GET /salons/mine and rendered in the app's «Контакти» block alongside instagramUrl. Not personal data of a natural person, so §I does not apply. Optional — a salon may have none.
/// * [instagramUrl]
/// * [avatarUrl]
/// * [coverImageUrl]
/// * [avgRating]
/// * [reviewCount]
@BuiltValue()
abstract class PublicSalonResponse
    implements Built<PublicSalonResponse, PublicSalonResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'description')
  String? get description;

  @BuiltValueField(wireName: r'city')
  String? get city;

  @BuiltValueField(wireName: r'region')
  String? get region;

  @BuiltValueField(wireName: r'address')
  String? get address;

  /// Taxonomy city. Every salon has one — salons.city_id is DB-level NOT NULL (V150/V151) and application-enforced from Phase 10.6 (LocalityWriteValidator). Never null on the wire.
  @BuiltValueField(wireName: r'cityId')
  String get cityId;

  /// Parent oblast of cityId, resolved at read time (see #from). cities.oblast_id is itself DB-level NOT NULL with a FK to oblasts, and cityId is guaranteed non-null and FK-valid, so resolution always succeeds. Never null on the wire.
  @BuiltValueField(wireName: r'oblastId')
  String get oblastId;

  @BuiltValueField(wireName: r'districtId')
  String? get districtId;

  @BuiltValueField(wireName: r'street')
  String? get street;

  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  /// Salon's public business contact number. Intentionally exposed on this permitAll path: it is the contact clients are meant to call, the same value already returned by GET /salons/mine and rendered in the app's «Контакти» block alongside instagramUrl. Not personal data of a natural person, so §I does not apply. Optional — a salon may have none.
  @BuiltValueField(wireName: r'phone')
  String? get phone;

  @BuiltValueField(wireName: r'instagramUrl')
  String? get instagramUrl;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'coverImageUrl')
  String? get coverImageUrl;

  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int? get reviewCount;

  PublicSalonResponse._();

  factory PublicSalonResponse([void updates(PublicSalonResponseBuilder b)]) =
      _$PublicSalonResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PublicSalonResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PublicSalonResponse> get serializer =>
      _$PublicSalonResponseSerializer();
}

class _$PublicSalonResponseSerializer
    implements PrimitiveSerializer<PublicSalonResponse> {
  @override
  final Iterable<Type> types = const [
    PublicSalonResponse,
    _$PublicSalonResponse
  ];

  @override
  final String wireName = r'PublicSalonResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PublicSalonResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    if (object.description != null) {
      yield r'description';
      yield serializers.serialize(
        object.description,
        specifiedType: const FullType(String),
      );
    }
    if (object.city != null) {
      yield r'city';
      yield serializers.serialize(
        object.city,
        specifiedType: const FullType(String),
      );
    }
    if (object.region != null) {
      yield r'region';
      yield serializers.serialize(
        object.region,
        specifiedType: const FullType(String),
      );
    }
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
    yield r'cityId';
    yield serializers.serialize(
      object.cityId,
      specifiedType: const FullType(String),
    );
    yield r'oblastId';
    yield serializers.serialize(
      object.oblastId,
      specifiedType: const FullType(String),
    );
    if (object.districtId != null) {
      yield r'districtId';
      yield serializers.serialize(
        object.districtId,
        specifiedType: const FullType(String),
      );
    }
    if (object.street != null) {
      yield r'street';
      yield serializers.serialize(
        object.street,
        specifiedType: const FullType(String),
      );
    }
    if (object.buildingNo != null) {
      yield r'buildingNo';
      yield serializers.serialize(
        object.buildingNo,
        specifiedType: const FullType(String),
      );
    }
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType(String),
      );
    }
    if (object.phone != null) {
      yield r'phone';
      yield serializers.serialize(
        object.phone,
        specifiedType: const FullType(String),
      );
    }
    if (object.instagramUrl != null) {
      yield r'instagramUrl';
      yield serializers.serialize(
        object.instagramUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.coverImageUrl != null) {
      yield r'coverImageUrl';
      yield serializers.serialize(
        object.coverImageUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.avgRating != null) {
      yield r'avgRating';
      yield serializers.serialize(
        object.avgRating,
        specifiedType: const FullType(num),
      );
    }
    if (object.reviewCount != null) {
      yield r'reviewCount';
      yield serializers.serialize(
        object.reviewCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PublicSalonResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PublicSalonResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        case r'city':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.city = valueDes;
          break;
        case r'region':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.region = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'cityId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityId = valueDes;
          break;
        case r'oblastId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.oblastId = valueDes;
          break;
        case r'districtId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.districtId = valueDes;
          break;
        case r'street':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.street = valueDes;
          break;
        case r'buildingNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.buildingNo = valueDes;
          break;
        case r'locationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.locationNote = valueDes;
          break;
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        case r'instagramUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.instagramUrl = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        case r'coverImageUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.coverImageUrl = valueDes;
          break;
        case r'avgRating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.avgRating = valueDes;
          break;
        case r'reviewCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PublicSalonResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PublicSalonResponseBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
