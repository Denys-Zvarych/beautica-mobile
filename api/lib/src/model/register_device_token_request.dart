//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'register_device_token_request.g.dart';

/// RegisterDeviceTokenRequest
///
/// Properties:
/// * [token]
/// * [platform]
@BuiltValue()
abstract class RegisterDeviceTokenRequest
    implements
        Built<RegisterDeviceTokenRequest, RegisterDeviceTokenRequestBuilder> {
  @BuiltValueField(wireName: r'token')
  String get token;

  @BuiltValueField(wireName: r'platform')
  String get platform;

  RegisterDeviceTokenRequest._();

  factory RegisterDeviceTokenRequest(
          [void updates(RegisterDeviceTokenRequestBuilder b)]) =
      _$RegisterDeviceTokenRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegisterDeviceTokenRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegisterDeviceTokenRequest> get serializer =>
      _$RegisterDeviceTokenRequestSerializer();
}

class _$RegisterDeviceTokenRequestSerializer
    implements PrimitiveSerializer<RegisterDeviceTokenRequest> {
  @override
  final Iterable<Type> types = const [
    RegisterDeviceTokenRequest,
    _$RegisterDeviceTokenRequest
  ];

  @override
  final String wireName = r'RegisterDeviceTokenRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegisterDeviceTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
    yield r'platform';
    yield serializers.serialize(
      object.platform,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RegisterDeviceTokenRequest object, {
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
    required RegisterDeviceTokenRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        case r'platform':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.platform = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegisterDeviceTokenRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegisterDeviceTokenRequestBuilder();
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
