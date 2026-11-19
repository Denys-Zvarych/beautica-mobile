//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'registration_otp_send_request.g.dart';

/// RegistrationOtpSendRequest
///
/// Properties:
/// * [phone]
/// * [smsFormat] - Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND.
@BuiltValue()
abstract class RegistrationOtpSendRequest
    implements
        Built<RegistrationOtpSendRequest, RegistrationOtpSendRequestBuilder> {
  @BuiltValueField(wireName: r'phone')
  String get phone;

  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND.
  @BuiltValueField(wireName: r'smsFormat')
  RegistrationOtpSendRequestSmsFormatEnum? get smsFormat;
  // enum smsFormatEnum {  DOMAIN_BOUND,  PLAIN,  };

  RegistrationOtpSendRequest._();

  factory RegistrationOtpSendRequest(
          [void updates(RegistrationOtpSendRequestBuilder b)]) =
      _$RegistrationOtpSendRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegistrationOtpSendRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegistrationOtpSendRequest> get serializer =>
      _$RegistrationOtpSendRequestSerializer();
}

class _$RegistrationOtpSendRequestSerializer
    implements PrimitiveSerializer<RegistrationOtpSendRequest> {
  @override
  final Iterable<Type> types = const [
    RegistrationOtpSendRequest,
    _$RegistrationOtpSendRequest
  ];

  @override
  final String wireName = r'RegistrationOtpSendRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegistrationOtpSendRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone';
    yield serializers.serialize(
      object.phone,
      specifiedType: const FullType(String),
    );
    if (object.smsFormat != null) {
      yield r'smsFormat';
      yield serializers.serialize(
        object.smsFormat,
        specifiedType: const FullType(RegistrationOtpSendRequestSmsFormatEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RegistrationOtpSendRequest object, {
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
    required RegistrationOtpSendRequestBuilder result,
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
        case r'smsFormat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(RegistrationOtpSendRequestSmsFormatEnum),
          ) as RegistrationOtpSendRequestSmsFormatEnum;
          result.smsFormat = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegistrationOtpSendRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegistrationOtpSendRequestBuilder();
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

class RegistrationOtpSendRequestSmsFormatEnum extends EnumClass {
  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND.
  @BuiltValueEnumConst(wireName: r'DOMAIN_BOUND')
  static const RegistrationOtpSendRequestSmsFormatEnum DOMAIN_BOUND =
      _$registrationOtpSendRequestSmsFormatEnum_DOMAIN_BOUND;

  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND.
  @BuiltValueEnumConst(wireName: r'PLAIN')
  static const RegistrationOtpSendRequestSmsFormatEnum PLAIN =
      _$registrationOtpSendRequestSmsFormatEnum_PLAIN;

  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const RegistrationOtpSendRequestSmsFormatEnum unknownDefaultOpenApi =
      _$registrationOtpSendRequestSmsFormatEnum_unknownDefaultOpenApi;

  static Serializer<RegistrationOtpSendRequestSmsFormatEnum> get serializer =>
      _$registrationOtpSendRequestSmsFormatEnumSerializer;

  const RegistrationOtpSendRequestSmsFormatEnum._(String name) : super(name);

  static BuiltSet<RegistrationOtpSendRequestSmsFormatEnum> get values =>
      _$registrationOtpSendRequestSmsFormatEnumValues;
  static RegistrationOtpSendRequestSmsFormatEnum valueOf(String name) =>
      _$registrationOtpSendRequestSmsFormatEnumValueOf(name);
}
