//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/available_slots_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_available_slots_response.g.dart';

/// ApiResponseAvailableSlotsResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
@BuiltValue()
abstract class ApiResponseAvailableSlotsResponse
    implements
        Built<ApiResponseAvailableSlotsResponse,
            ApiResponseAvailableSlotsResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  AvailableSlotsResponse? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  ApiResponseAvailableSlotsResponse._();

  factory ApiResponseAvailableSlotsResponse(
          [void updates(ApiResponseAvailableSlotsResponseBuilder b)]) =
      _$ApiResponseAvailableSlotsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponseAvailableSlotsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseAvailableSlotsResponse> get serializer =>
      _$ApiResponseAvailableSlotsResponseSerializer();
}

class _$ApiResponseAvailableSlotsResponseSerializer
    implements PrimitiveSerializer<ApiResponseAvailableSlotsResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponseAvailableSlotsResponse,
    _$ApiResponseAvailableSlotsResponse
  ];

  @override
  final String wireName = r'ApiResponseAvailableSlotsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseAvailableSlotsResponse object, {
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
        specifiedType: const FullType(AvailableSlotsResponse),
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
    ApiResponseAvailableSlotsResponse object, {
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
    required ApiResponseAvailableSlotsResponseBuilder result,
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
            specifiedType: const FullType(AvailableSlotsResponse),
          ) as AvailableSlotsResponse;
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
  ApiResponseAvailableSlotsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponseAvailableSlotsResponseBuilder();
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
