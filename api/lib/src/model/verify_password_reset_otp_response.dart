//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'verify_password_reset_otp_response.g.dart';

/// VerifyPasswordResetOtpResponse
///
/// Properties:
/// * [resetTicket]
@BuiltValue()
abstract class VerifyPasswordResetOtpResponse
    implements
        Built<VerifyPasswordResetOtpResponse,
            VerifyPasswordResetOtpResponseBuilder> {
  @BuiltValueField(wireName: r'resetTicket')
  String? get resetTicket;

  VerifyPasswordResetOtpResponse._();

  factory VerifyPasswordResetOtpResponse(
          [void updates(VerifyPasswordResetOtpResponseBuilder b)]) =
      _$VerifyPasswordResetOtpResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VerifyPasswordResetOtpResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VerifyPasswordResetOtpResponse> get serializer =>
      _$VerifyPasswordResetOtpResponseSerializer();
}

class _$VerifyPasswordResetOtpResponseSerializer
    implements PrimitiveSerializer<VerifyPasswordResetOtpResponse> {
  @override
  final Iterable<Type> types = const [
    VerifyPasswordResetOtpResponse,
    _$VerifyPasswordResetOtpResponse
  ];

  @override
  final String wireName = r'VerifyPasswordResetOtpResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VerifyPasswordResetOtpResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.resetTicket != null) {
      yield r'resetTicket';
      yield serializers.serialize(
        object.resetTicket,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    VerifyPasswordResetOtpResponse object, {
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
    required VerifyPasswordResetOtpResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'resetTicket':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.resetTicket = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VerifyPasswordResetOtpResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VerifyPasswordResetOtpResponseBuilder();
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
