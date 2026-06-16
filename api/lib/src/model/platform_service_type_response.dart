//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'platform_service_type_response.g.dart';

/// PlatformServiceTypeResponse
///
/// Properties:
/// * [id]
/// * [slug]
/// * [nameUk]
/// * [categoryName]
@BuiltValue()
abstract class PlatformServiceTypeResponse
    implements
        Built<PlatformServiceTypeResponse, PlatformServiceTypeResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'slug')
  String? get slug;

  @BuiltValueField(wireName: r'nameUk')
  String? get nameUk;

  @BuiltValueField(wireName: r'categoryName')
  String? get categoryName;

  PlatformServiceTypeResponse._();

  factory PlatformServiceTypeResponse(
          [void updates(PlatformServiceTypeResponseBuilder b)]) =
      _$PlatformServiceTypeResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlatformServiceTypeResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlatformServiceTypeResponse> get serializer =>
      _$PlatformServiceTypeResponseSerializer();
}

class _$PlatformServiceTypeResponseSerializer
    implements PrimitiveSerializer<PlatformServiceTypeResponse> {
  @override
  final Iterable<Type> types = const [
    PlatformServiceTypeResponse,
    _$PlatformServiceTypeResponse
  ];

  @override
  final String wireName = r'PlatformServiceTypeResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlatformServiceTypeResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.slug != null) {
      yield r'slug';
      yield serializers.serialize(
        object.slug,
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
    if (object.categoryName != null) {
      yield r'categoryName';
      yield serializers.serialize(
        object.categoryName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlatformServiceTypeResponse object, {
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
    required PlatformServiceTypeResponseBuilder result,
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
        case r'slug':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.slug = valueDes;
          break;
        case r'nameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameUk = valueDes;
          break;
        case r'categoryName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.categoryName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlatformServiceTypeResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlatformServiceTypeResponseBuilder();
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
