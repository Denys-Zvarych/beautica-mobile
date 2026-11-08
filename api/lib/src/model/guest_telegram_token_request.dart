//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_telegram_token_request.g.dart';

/// GuestTelegramTokenRequest
///
/// Properties:
/// * [cancelToken]
@BuiltValue()
abstract class GuestTelegramTokenRequest
    implements
        Built<GuestTelegramTokenRequest, GuestTelegramTokenRequestBuilder> {
  @BuiltValueField(wireName: r'cancelToken')
  String get cancelToken;

  GuestTelegramTokenRequest._();

  factory GuestTelegramTokenRequest(
          [void updates(GuestTelegramTokenRequestBuilder b)]) =
      _$GuestTelegramTokenRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestTelegramTokenRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestTelegramTokenRequest> get serializer =>
      _$GuestTelegramTokenRequestSerializer();
}

class _$GuestTelegramTokenRequestSerializer
    implements PrimitiveSerializer<GuestTelegramTokenRequest> {
  @override
  final Iterable<Type> types = const [
    GuestTelegramTokenRequest,
    _$GuestTelegramTokenRequest
  ];

  @override
  final String wireName = r'GuestTelegramTokenRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestTelegramTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cancelToken';
    yield serializers.serialize(
      object.cancelToken,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestTelegramTokenRequest object, {
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
    required GuestTelegramTokenRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cancelToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancelToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestTelegramTokenRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestTelegramTokenRequestBuilder();
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
