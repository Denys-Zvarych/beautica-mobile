//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/service_type_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_list_service_type_response.g.dart';

/// ApiResponseListServiceTypeResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
@BuiltValue()
abstract class ApiResponseListServiceTypeResponse
    implements
        Built<ApiResponseListServiceTypeResponse,
            ApiResponseListServiceTypeResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  BuiltList<ServiceTypeResponse>? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  ApiResponseListServiceTypeResponse._();

  factory ApiResponseListServiceTypeResponse(
          [void updates(ApiResponseListServiceTypeResponseBuilder b)]) =
      _$ApiResponseListServiceTypeResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponseListServiceTypeResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseListServiceTypeResponse> get serializer =>
      _$ApiResponseListServiceTypeResponseSerializer();
}

class _$ApiResponseListServiceTypeResponseSerializer
    implements PrimitiveSerializer<ApiResponseListServiceTypeResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponseListServiceTypeResponse,
    _$ApiResponseListServiceTypeResponse
  ];

  @override
  final String wireName = r'ApiResponseListServiceTypeResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseListServiceTypeResponse object, {
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
        specifiedType:
            const FullType(BuiltList, [FullType(ServiceTypeResponse)]),
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
    ApiResponseListServiceTypeResponse object, {
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
    required ApiResponseListServiceTypeResponseBuilder result,
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
            specifiedType:
                const FullType(BuiltList, [FullType(ServiceTypeResponse)]),
          ) as BuiltList<ServiceTypeResponse>;
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
  ApiResponseListServiceTypeResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponseListServiceTypeResponseBuilder();
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
