//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'registration_otp_verify_request.g.dart';

/// RegistrationOtpVerifyRequest
///
/// Properties:
/// * [phone]
/// * [code]
@BuiltValue()
abstract class RegistrationOtpVerifyRequest
    implements
        Built<RegistrationOtpVerifyRequest,
            RegistrationOtpVerifyRequestBuilder> {
  @BuiltValueField(wireName: r'phone')
  String get phone;

  @BuiltValueField(wireName: r'code')
  String get code;

  RegistrationOtpVerifyRequest._();

  factory RegistrationOtpVerifyRequest(
          [void updates(RegistrationOtpVerifyRequestBuilder b)]) =
      _$RegistrationOtpVerifyRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegistrationOtpVerifyRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegistrationOtpVerifyRequest> get serializer =>
      _$RegistrationOtpVerifyRequestSerializer();
}

class _$RegistrationOtpVerifyRequestSerializer
    implements PrimitiveSerializer<RegistrationOtpVerifyRequest> {
  @override
  final Iterable<Type> types = const [
    RegistrationOtpVerifyRequest,
    _$RegistrationOtpVerifyRequest
  ];

  @override
  final String wireName = r'RegistrationOtpVerifyRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegistrationOtpVerifyRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone';
    yield serializers.serialize(
      object.phone,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RegistrationOtpVerifyRequest object, {
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
    required RegistrationOtpVerifyRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegistrationOtpVerifyRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegistrationOtpVerifyRequestBuilder();
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
