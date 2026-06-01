//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/platform_category_usage_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_list_platform_category_usage_response.g.dart';

/// ApiResponseListPlatformCategoryUsageResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
@BuiltValue()
abstract class ApiResponseListPlatformCategoryUsageResponse
    implements
        Built<ApiResponseListPlatformCategoryUsageResponse,
            ApiResponseListPlatformCategoryUsageResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  BuiltList<PlatformCategoryUsageResponse>? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  ApiResponseListPlatformCategoryUsageResponse._();

  factory ApiResponseListPlatformCategoryUsageResponse(
          [void updates(
              ApiResponseListPlatformCategoryUsageResponseBuilder b)]) =
      _$ApiResponseListPlatformCategoryUsageResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(
          ApiResponseListPlatformCategoryUsageResponseBuilder b) =>
      b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseListPlatformCategoryUsageResponse>
      get serializer =>
          _$ApiResponseListPlatformCategoryUsageResponseSerializer();
}

class _$ApiResponseListPlatformCategoryUsageResponseSerializer
    implements
        PrimitiveSerializer<ApiResponseListPlatformCategoryUsageResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponseListPlatformCategoryUsageResponse,
    _$ApiResponseListPlatformCategoryUsageResponse
  ];

  @override
  final String wireName = r'ApiResponseListPlatformCategoryUsageResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseListPlatformCategoryUsageResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.success != null) {
      yield r'success';
      yield serializers.serialize(
        object.success,
        specifiedType: const FullType(bool),
      );
    }
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(
            BuiltList, [FullType(PlatformCategoryUsageResponse)]),
      );
    }
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApiResponseListPlatformCategoryUsageResponse object, {
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
    required ApiResponseListPlatformCategoryUsageResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(
                BuiltList, [FullType(PlatformCategoryUsageResponse)]),
          ) as BuiltList<PlatformCategoryUsageResponse>;
          result.data.replace(valueDes);
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApiResponseListPlatformCategoryUsageResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponseListPlatformCategoryUsageResponseBuilder();
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
