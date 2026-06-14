//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/page_response_review_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_page_response_review_response.g.dart';

/// ApiResponsePageResponseReviewResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
/// * [errors]
@BuiltValue()
abstract class ApiResponsePageResponseReviewResponse
    implements
        Built<ApiResponsePageResponseReviewResponse,
            ApiResponsePageResponseReviewResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  PageResponseReviewResponse? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  @BuiltValueField(wireName: r'errors')
  BuiltMap<String, String>? get errors;

  ApiResponsePageResponseReviewResponse._();

  factory ApiResponsePageResponseReviewResponse(
          [void updates(ApiResponsePageResponseReviewResponseBuilder b)]) =
      _$ApiResponsePageResponseReviewResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponsePageResponseReviewResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponsePageResponseReviewResponse> get serializer =>
      _$ApiResponsePageResponseReviewResponseSerializer();
}

class _$ApiResponsePageResponseReviewResponseSerializer
    implements PrimitiveSerializer<ApiResponsePageResponseReviewResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponsePageResponseReviewResponse,
    _$ApiResponsePageResponseReviewResponse
  ];

  @override
  final String wireName = r'ApiResponsePageResponseReviewResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponsePageResponseReviewResponse object, {
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
        specifiedType: const FullType(PageResponseReviewResponse),
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
    ApiResponsePageResponseReviewResponse object, {
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
    required ApiResponsePageResponseReviewResponseBuilder result,
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
            specifiedType: const FullType(PageResponseReviewResponse),
          ) as PageResponseReviewResponse;
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
  ApiResponsePageResponseReviewResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponsePageResponseReviewResponseBuilder();
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
