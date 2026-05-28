//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/page_media_file_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_page_media_file_response.g.dart';

/// ApiResponsePageMediaFileResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
@BuiltValue()
abstract class ApiResponsePageMediaFileResponse
    implements
        Built<ApiResponsePageMediaFileResponse,
            ApiResponsePageMediaFileResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  PageMediaFileResponse? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  ApiResponsePageMediaFileResponse._();

  factory ApiResponsePageMediaFileResponse(
          [void updates(ApiResponsePageMediaFileResponseBuilder b)]) =
      _$ApiResponsePageMediaFileResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponsePageMediaFileResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponsePageMediaFileResponse> get serializer =>
      _$ApiResponsePageMediaFileResponseSerializer();
}

class _$ApiResponsePageMediaFileResponseSerializer
    implements PrimitiveSerializer<ApiResponsePageMediaFileResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponsePageMediaFileResponse,
    _$ApiResponsePageMediaFileResponse
  ];

  @override
  final String wireName = r'ApiResponsePageMediaFileResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponsePageMediaFileResponse object, {
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
        specifiedType: const FullType(PageMediaFileResponse),
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
    ApiResponsePageMediaFileResponse object, {
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
    required ApiResponsePageMediaFileResponseBuilder result,
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
            specifiedType: const FullType(PageMediaFileResponse),
          ) as PageMediaFileResponse;
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
  ApiResponsePageMediaFileResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponsePageMediaFileResponseBuilder();
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
