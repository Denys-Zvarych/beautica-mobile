//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/master_public_profile_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_master_public_profile_response.g.dart';

/// ApiResponseMasterPublicProfileResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
@BuiltValue()
abstract class ApiResponseMasterPublicProfileResponse
    implements
        Built<ApiResponseMasterPublicProfileResponse,
            ApiResponseMasterPublicProfileResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  MasterPublicProfileResponse? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  ApiResponseMasterPublicProfileResponse._();

  factory ApiResponseMasterPublicProfileResponse(
          [void updates(ApiResponseMasterPublicProfileResponseBuilder b)]) =
      _$ApiResponseMasterPublicProfileResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponseMasterPublicProfileResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseMasterPublicProfileResponse> get serializer =>
      _$ApiResponseMasterPublicProfileResponseSerializer();
}

class _$ApiResponseMasterPublicProfileResponseSerializer
    implements PrimitiveSerializer<ApiResponseMasterPublicProfileResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponseMasterPublicProfileResponse,
    _$ApiResponseMasterPublicProfileResponse
  ];

  @override
  final String wireName = r'ApiResponseMasterPublicProfileResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseMasterPublicProfileResponse object, {
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
        specifiedType: const FullType(MasterPublicProfileResponse),
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
    ApiResponseMasterPublicProfileResponse object, {
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
    required ApiResponseMasterPublicProfileResponseBuilder result,
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
            specifiedType: const FullType(MasterPublicProfileResponse),
          ) as MasterPublicProfileResponse;
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
  ApiResponseMasterPublicProfileResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponseMasterPublicProfileResponseBuilder();
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
