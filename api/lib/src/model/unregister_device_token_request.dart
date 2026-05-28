//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unregister_device_token_request.g.dart';

/// UnregisterDeviceTokenRequest
///
/// Properties:
/// * [token]
@BuiltValue()
abstract class UnregisterDeviceTokenRequest
    implements
        Built<UnregisterDeviceTokenRequest,
            UnregisterDeviceTokenRequestBuilder> {
  @BuiltValueField(wireName: r'token')
  String get token;

  UnregisterDeviceTokenRequest._();

  factory UnregisterDeviceTokenRequest(
          [void updates(UnregisterDeviceTokenRequestBuilder b)]) =
      _$UnregisterDeviceTokenRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UnregisterDeviceTokenRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UnregisterDeviceTokenRequest> get serializer =>
      _$UnregisterDeviceTokenRequestSerializer();
}

class _$UnregisterDeviceTokenRequestSerializer
    implements PrimitiveSerializer<UnregisterDeviceTokenRequest> {
  @override
  final Iterable<Type> types = const [
    UnregisterDeviceTokenRequest,
    _$UnregisterDeviceTokenRequest
  ];

  @override
  final String wireName = r'UnregisterDeviceTokenRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UnregisterDeviceTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UnregisterDeviceTokenRequest object, {
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
    required UnregisterDeviceTokenRequestBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UnregisterDeviceTokenRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UnregisterDeviceTokenRequestBuilder();
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
