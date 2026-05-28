//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'oblast_response.g.dart';

/// OblastResponse
///
/// Properties:
/// * [id]
/// * [katotthCode]
/// * [nameUk]
/// * [nameEn]
@BuiltValue()
abstract class OblastResponse
    implements Built<OblastResponse, OblastResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'katotthCode')
  String? get katotthCode;

  @BuiltValueField(wireName: r'nameUk')
  String? get nameUk;

  @BuiltValueField(wireName: r'nameEn')
  String? get nameEn;

  OblastResponse._();

  factory OblastResponse([void updates(OblastResponseBuilder b)]) =
      _$OblastResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OblastResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OblastResponse> get serializer =>
      _$OblastResponseSerializer();
}

class _$OblastResponseSerializer
    implements PrimitiveSerializer<OblastResponse> {
  @override
  final Iterable<Type> types = const [OblastResponse, _$OblastResponse];

  @override
  final String wireName = r'OblastResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OblastResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
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
    OblastResponse object, {
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
    required OblastResponseBuilder result,
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
  OblastResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OblastResponseBuilder();
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
