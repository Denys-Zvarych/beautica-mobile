//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/page_response_salon_search_result.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_page_response_salon_search_result.g.dart';

/// ApiResponsePageResponseSalonSearchResult
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
@BuiltValue()
abstract class ApiResponsePageResponseSalonSearchResult
    implements
        Built<ApiResponsePageResponseSalonSearchResult,
            ApiResponsePageResponseSalonSearchResultBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  PageResponseSalonSearchResult? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  ApiResponsePageResponseSalonSearchResult._();

  factory ApiResponsePageResponseSalonSearchResult(
          [void updates(ApiResponsePageResponseSalonSearchResultBuilder b)]) =
      _$ApiResponsePageResponseSalonSearchResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponsePageResponseSalonSearchResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponsePageResponseSalonSearchResult> get serializer =>
      _$ApiResponsePageResponseSalonSearchResultSerializer();
}

class _$ApiResponsePageResponseSalonSearchResultSerializer
    implements PrimitiveSerializer<ApiResponsePageResponseSalonSearchResult> {
  @override
  final Iterable<Type> types = const [
    ApiResponsePageResponseSalonSearchResult,
    _$ApiResponsePageResponseSalonSearchResult
  ];

  @override
  final String wireName = r'ApiResponsePageResponseSalonSearchResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponsePageResponseSalonSearchResult object, {
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
        specifiedType: const FullType(PageResponseSalonSearchResult),
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
    ApiResponsePageResponseSalonSearchResult object, {
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
    required ApiResponsePageResponseSalonSearchResultBuilder result,
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
            specifiedType: const FullType(PageResponseSalonSearchResult),
          ) as PageResponseSalonSearchResult;
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
  ApiResponsePageResponseSalonSearchResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponsePageResponseSalonSearchResultBuilder();
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
