//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'city_district_response.g.dart';

/// CityDistrictResponse
///
/// Properties:
/// * [id]
/// * [cityId]
/// * [katotthCode]
/// * [nameUk]
/// * [nameEn]
@BuiltValue()
abstract class CityDistrictResponse
    implements Built<CityDistrictResponse, CityDistrictResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'cityId')
  String? get cityId;

  @BuiltValueField(wireName: r'katotthCode')
  String? get katotthCode;

  @BuiltValueField(wireName: r'nameUk')
  String? get nameUk;

  @BuiltValueField(wireName: r'nameEn')
  String? get nameEn;

  CityDistrictResponse._();

  factory CityDistrictResponse([void updates(CityDistrictResponseBuilder b)]) =
      _$CityDistrictResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CityDistrictResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CityDistrictResponse> get serializer =>
      _$CityDistrictResponseSerializer();
}

class _$CityDistrictResponseSerializer
    implements PrimitiveSerializer<CityDistrictResponse> {
  @override
  final Iterable<Type> types = const [
    CityDistrictResponse,
    _$CityDistrictResponse
  ];

  @override
  final String wireName = r'CityDistrictResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CityDistrictResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
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
    if (object.katotthCode != null) {
      yield r'katotthCode';
      yield serializers.serialize(
        object.katotthCode,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameUk != null) {
      yield r'nameUk';
      yield serializers.serialize(
        object.nameUk,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameEn != null) {
      yield r'nameEn';
      yield serializers.serialize(
        object.nameEn,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CityDistrictResponse object, {
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
    required CityDistrictResponseBuilder result,
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
        case r'cityId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityId = valueDes;
          break;
        case r'katotthCode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.katotthCode = valueDes;
          break;
        case r'nameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameUk = valueDes;
          break;
        case r'nameEn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameEn = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CityDistrictResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CityDistrictResponseBuilder();
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
