//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_salon_request.g.dart';

/// CreateSalonRequest
///
/// Properties:
/// * [name]
/// * [description]
/// * [city]
/// * [region]
/// * [address]
/// * [phone]
/// * [instagramUrl]
/// * [cityId]
/// * [districtId]
/// * [street]
/// * [buildingNo]
/// * [locationNote]
@BuiltValue()
abstract class CreateSalonRequest
    implements Built<CreateSalonRequest, CreateSalonRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'description')
  String? get description;

  @BuiltValueField(wireName: r'city')
  String? get city;

  @BuiltValueField(wireName: r'region')
  String? get region;

  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'phone')
  String? get phone;

  @BuiltValueField(wireName: r'instagramUrl')
  String? get instagramUrl;

  @BuiltValueField(wireName: r'cityId')
  String? get cityId;

  @BuiltValueField(wireName: r'districtId')
  String? get districtId;

  @BuiltValueField(wireName: r'street')
  String get street;

  @BuiltValueField(wireName: r'buildingNo')
  String get buildingNo;

  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  CreateSalonRequest._();

  factory CreateSalonRequest([void updates(CreateSalonRequestBuilder b)]) =
      _$CreateSalonRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateSalonRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateSalonRequest> get serializer =>
      _$CreateSalonRequestSerializer();
}

class _$CreateSalonRequestSerializer
    implements PrimitiveSerializer<CreateSalonRequest> {
  @override
  final Iterable<Type> types = const [CreateSalonRequest, _$CreateSalonRequest];

  @override
  final String wireName = r'CreateSalonRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateSalonRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
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
    if (object.cityId != null) {
      yield r'cityId';
      yield serializers.serialize(
        object.cityId,
        specifiedType: const FullType(String),
      );
    }
    if (object.districtId != null) {
      yield r'districtId';
      yield serializers.serialize(
        object.districtId,
        specifiedType: const FullType(String),
      );
    }
    yield r'street';
    yield serializers.serialize(
      object.street,
      specifiedType: const FullType(String),
    );
    yield r'buildingNo';
    yield serializers.serialize(
      object.buildingNo,
      specifiedType: const FullType(String),
    );
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateSalonRequest object, {
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
    required CreateSalonRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'cityId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityId = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateSalonRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateSalonRequestBuilder();
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
