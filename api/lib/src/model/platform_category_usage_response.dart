//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'platform_category_usage_response.g.dart';

/// PlatformCategoryUsageResponse
///
/// Properties:
/// * [name]
/// * [active]
/// * [usageCount]
@BuiltValue()
abstract class PlatformCategoryUsageResponse
    implements
        Built<PlatformCategoryUsageResponse,
            PlatformCategoryUsageResponseBuilder> {
  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'active')
  bool? get active;

  @BuiltValueField(wireName: r'usageCount')
  int? get usageCount;

  PlatformCategoryUsageResponse._();

  factory PlatformCategoryUsageResponse(
          [void updates(PlatformCategoryUsageResponseBuilder b)]) =
      _$PlatformCategoryUsageResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlatformCategoryUsageResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlatformCategoryUsageResponse> get serializer =>
      _$PlatformCategoryUsageResponseSerializer();
}

class _$PlatformCategoryUsageResponseSerializer
    implements PrimitiveSerializer<PlatformCategoryUsageResponse> {
  @override
  final Iterable<Type> types = const [
    PlatformCategoryUsageResponse,
    _$PlatformCategoryUsageResponse
  ];

  @override
  final String wireName = r'PlatformCategoryUsageResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlatformCategoryUsageResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    if (object.active != null) {
      yield r'active';
      yield serializers.serialize(
        object.active,
        specifiedType: const FullType(bool),
      );
    }
    if (object.usageCount != null) {
      yield r'usageCount';
      yield serializers.serialize(
        object.usageCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlatformCategoryUsageResponse object, {
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
    required PlatformCategoryUsageResponseBuilder result,
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
        case r'active':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.active = valueDes;
          break;
        case r'usageCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.usageCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlatformCategoryUsageResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlatformCategoryUsageResponseBuilder();
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
