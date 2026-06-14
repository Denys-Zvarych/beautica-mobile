//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/category_request_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_category_request_response.g.dart';

/// ApiResponseCategoryRequestResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
/// * [errors]
@BuiltValue()
abstract class ApiResponseCategoryRequestResponse
    implements
        Built<ApiResponseCategoryRequestResponse,
            ApiResponseCategoryRequestResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  CategoryRequestResponse? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  @BuiltValueField(wireName: r'errors')
  BuiltMap<String, String>? get errors;

  ApiResponseCategoryRequestResponse._();

  factory ApiResponseCategoryRequestResponse(
          [void updates(ApiResponseCategoryRequestResponseBuilder b)]) =
      _$ApiResponseCategoryRequestResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponseCategoryRequestResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseCategoryRequestResponse> get serializer =>
      _$ApiResponseCategoryRequestResponseSerializer();
}

class _$ApiResponseCategoryRequestResponseSerializer
    implements PrimitiveSerializer<ApiResponseCategoryRequestResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponseCategoryRequestResponse,
    _$ApiResponseCategoryRequestResponse
  ];

  @override
  final String wireName = r'ApiResponseCategoryRequestResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseCategoryRequestResponse object, {
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
        specifiedType: const FullType(CategoryRequestResponse),
      );
    }
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
    if (object.errors != null) {
      yield r'errors';
      yield serializers.serialize(
        object.errors,
        specifiedType:
            const FullType(BuiltMap, [FullType(String), FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApiResponseCategoryRequestResponse object, {
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
    required ApiResponseCategoryRequestResponseBuilder result,
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
            specifiedType: const FullType(CategoryRequestResponse),
          ) as CategoryRequestResponse;
          result.data.replace(valueDes);
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'errors':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.errors.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApiResponseCategoryRequestResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponseCategoryRequestResponseBuilder();
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
