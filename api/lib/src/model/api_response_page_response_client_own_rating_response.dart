//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/page_response_client_own_rating_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_page_response_client_own_rating_response.g.dart';

/// ApiResponsePageResponseClientOwnRatingResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
/// * [errors]
/// * [requestId]
@BuiltValue()
abstract class ApiResponsePageResponseClientOwnRatingResponse
    implements
        Built<ApiResponsePageResponseClientOwnRatingResponse,
            ApiResponsePageResponseClientOwnRatingResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  PageResponseClientOwnRatingResponse? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  @BuiltValueField(wireName: r'errors')
  BuiltMap<String, String>? get errors;

  @BuiltValueField(wireName: r'requestId')
  String? get requestId;

  ApiResponsePageResponseClientOwnRatingResponse._();

  factory ApiResponsePageResponseClientOwnRatingResponse(
          [void updates(
              ApiResponsePageResponseClientOwnRatingResponseBuilder b)]) =
      _$ApiResponsePageResponseClientOwnRatingResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(
          ApiResponsePageResponseClientOwnRatingResponseBuilder b) =>
      b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponsePageResponseClientOwnRatingResponse>
      get serializer =>
          _$ApiResponsePageResponseClientOwnRatingResponseSerializer();
}

class _$ApiResponsePageResponseClientOwnRatingResponseSerializer
    implements
        PrimitiveSerializer<ApiResponsePageResponseClientOwnRatingResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponsePageResponseClientOwnRatingResponse,
    _$ApiResponsePageResponseClientOwnRatingResponse
  ];

  @override
  final String wireName = r'ApiResponsePageResponseClientOwnRatingResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponsePageResponseClientOwnRatingResponse object, {
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
        specifiedType: const FullType(PageResponseClientOwnRatingResponse),
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
    if (object.requestId != null) {
      yield r'requestId';
      yield serializers.serialize(
        object.requestId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApiResponsePageResponseClientOwnRatingResponse object, {
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
    required ApiResponsePageResponseClientOwnRatingResponseBuilder result,
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
            specifiedType: const FullType(PageResponseClientOwnRatingResponse),
          ) as PageResponseClientOwnRatingResponse;
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
        case r'requestId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApiResponsePageResponseClientOwnRatingResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponsePageResponseClientOwnRatingResponseBuilder();
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
