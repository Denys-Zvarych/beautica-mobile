//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'verify_password_reset_otp_request.g.dart';

/// VerifyPasswordResetOtpRequest
///
/// Properties:
/// * [email] - Legacy (pre-B516): the account email. Prefer identifier.
/// * [code]
/// * [identifier] - B516: the same phone or email sent to forgot-password.
@BuiltValue()
abstract class VerifyPasswordResetOtpRequest
    implements
        Built<VerifyPasswordResetOtpRequest,
            VerifyPasswordResetOtpRequestBuilder> {
  /// Legacy (pre-B516): the account email. Prefer identifier.
  @BuiltValueField(wireName: r'email')
  String? get email;

  @BuiltValueField(wireName: r'code')
  String get code;

  /// B516: the same phone or email sent to forgot-password.
  @BuiltValueField(wireName: r'identifier')
  String? get identifier;

  VerifyPasswordResetOtpRequest._();

  factory VerifyPasswordResetOtpRequest(
          [void updates(VerifyPasswordResetOtpRequestBuilder b)]) =
      _$VerifyPasswordResetOtpRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VerifyPasswordResetOtpRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VerifyPasswordResetOtpRequest> get serializer =>
      _$VerifyPasswordResetOtpRequestSerializer();
}

class _$VerifyPasswordResetOtpRequestSerializer
    implements PrimitiveSerializer<VerifyPasswordResetOtpRequest> {
  @override
  final Iterable<Type> types = const [
    VerifyPasswordResetOtpRequest,
    _$VerifyPasswordResetOtpRequest
  ];

  @override
  final String wireName = r'VerifyPasswordResetOtpRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VerifyPasswordResetOtpRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.email != null) {
      yield r'email';
      yield serializers.serialize(
        object.email,
        specifiedType: const FullType(String),
      );
    }
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    if (object.identifier != null) {
      yield r'identifier';
      yield serializers.serialize(
        object.identifier,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    VerifyPasswordResetOtpRequest object, {
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
    required VerifyPasswordResetOtpRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'email':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.email = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'identifier':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.identifier = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VerifyPasswordResetOtpRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VerifyPasswordResetOtpRequestBuilder();
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
