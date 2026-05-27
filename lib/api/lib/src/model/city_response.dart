//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'city_response.g.dart';

/// CityResponse
///
/// Properties:
/// * [id]
/// * [oblastId]
/// * [katotthCode]
/// * [nameUk]
/// * [nameEn]
/// * [hasDistricts]
@BuiltValue()
abstract class CityResponse
    implements Built<CityResponse, CityResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'oblastId')
  String? get oblastId;

  @BuiltValueField(wireName: r'katotthCode')
  String? get katotthCode;

  @BuiltValueField(wireName: r'nameUk')
  String? get nameUk;

  @BuiltValueField(wireName: r'nameEn')
  String? get nameEn;

  @BuiltValueField(wireName: r'hasDistricts')
  bool? get hasDistricts;

  CityResponse._();

  factory CityResponse([void updates(CityResponseBuilder b)]) = _$CityResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CityResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CityResponse> get serializer => _$CityResponseSerializer();
}

class _$CityResponseSerializer implements PrimitiveSerializer<CityResponse> {
  @override
  final Iterable<Type> types = const [CityResponse, _$CityResponse];

  @override
  final String wireName = r'CityResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CityResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.oblastId != null) {
      yield r'oblastId';
      yield serializers.serialize(
        object.oblastId,
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
    if (object.hasDistricts != null) {
      yield r'hasDistricts';
      yield serializers.serialize(
        object.hasDistricts,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CityResponse object, {
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
    required CityResponseBuilder result,
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
        case r'oblastId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.oblastId = valueDes;
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
        case r'hasDistricts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasDistricts = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CityResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CityResponseBuilder();
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
