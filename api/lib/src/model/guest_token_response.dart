//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_token_response.g.dart';

/// GuestTokenResponse
///
/// Properties:
/// * [guestToken]
@BuiltValue()
abstract class GuestTokenResponse
    implements Built<GuestTokenResponse, GuestTokenResponseBuilder> {
  @BuiltValueField(wireName: r'guestToken')
  String? get guestToken;

  GuestTokenResponse._();

  factory GuestTokenResponse([void updates(GuestTokenResponseBuilder b)]) =
      _$GuestTokenResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestTokenResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestTokenResponse> get serializer =>
      _$GuestTokenResponseSerializer();
}

class _$GuestTokenResponseSerializer
    implements PrimitiveSerializer<GuestTokenResponse> {
  @override
  final Iterable<Type> types = const [GuestTokenResponse, _$GuestTokenResponse];

  @override
  final String wireName = r'GuestTokenResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestTokenResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.guestToken != null) {
      yield r'guestToken';
      yield serializers.serialize(
        object.guestToken,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestTokenResponse object, {
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
    required GuestTokenResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guestToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guestToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestTokenResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestTokenResponseBuilder();
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
