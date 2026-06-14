//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/review_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_review_response.g.dart';

/// ApiResponseReviewResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
/// * [errors]
@BuiltValue()
abstract class ApiResponseReviewResponse
    implements
        Built<ApiResponseReviewResponse, ApiResponseReviewResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  ReviewResponse? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  @BuiltValueField(wireName: r'errors')
  BuiltMap<String, String>? get errors;

  ApiResponseReviewResponse._();

  factory ApiResponseReviewResponse(
          [void updates(ApiResponseReviewResponseBuilder b)]) =
      _$ApiResponseReviewResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponseReviewResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseReviewResponse> get serializer =>
      _$ApiResponseReviewResponseSerializer();
}

class _$ApiResponseReviewResponseSerializer
    implements PrimitiveSerializer<ApiResponseReviewResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponseReviewResponse,
    _$ApiResponseReviewResponse
  ];

  @override
  final String wireName = r'ApiResponseReviewResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseReviewResponse object, {
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
        specifiedType: const FullType(ReviewResponse),
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
    ApiResponseReviewResponse object, {
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
    required ApiResponseReviewResponseBuilder result,
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
            specifiedType: const FullType(ReviewResponse),
          ) as ReviewResponse;
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
  ApiResponseReviewResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponseReviewResponseBuilder();
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
