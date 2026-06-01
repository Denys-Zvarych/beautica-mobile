//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_platform_category_request.g.dart';

/// CreatePlatformCategoryRequest
///
/// Properties:
/// * [name]
@BuiltValue()
abstract class CreatePlatformCategoryRequest
    implements
        Built<CreatePlatformCategoryRequest,
            CreatePlatformCategoryRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  CreatePlatformCategoryRequest._();

  factory CreatePlatformCategoryRequest(
          [void updates(CreatePlatformCategoryRequestBuilder b)]) =
      _$CreatePlatformCategoryRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreatePlatformCategoryRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreatePlatformCategoryRequest> get serializer =>
      _$CreatePlatformCategoryRequestSerializer();
}

class _$CreatePlatformCategoryRequestSerializer
    implements PrimitiveSerializer<CreatePlatformCategoryRequest> {
  @override
  final Iterable<Type> types = const [
    CreatePlatformCategoryRequest,
    _$CreatePlatformCategoryRequest
  ];

  @override
  final String wireName = r'CreatePlatformCategoryRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreatePlatformCategoryRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreatePlatformCategoryRequest object, {
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
    required CreatePlatformCategoryRequestBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreatePlatformCategoryRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreatePlatformCategoryRequestBuilder();
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
