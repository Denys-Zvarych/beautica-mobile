//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phone_otp_send_request.g.dart';

/// PhoneOtpSendRequest
///
/// Properties:
/// * [phone]
/// * [privacyAccepted]
/// * [privacyPolicyVersion]
/// * [turnstileToken] - Required when Turnstile is enabled (prod, staging).
/// * [smsFormat] - Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND (adds the origin-bound `@host #code` line).
@BuiltValue()
abstract class PhoneOtpSendRequest
    implements Built<PhoneOtpSendRequest, PhoneOtpSendRequestBuilder> {
  @BuiltValueField(wireName: r'phone')
  String get phone;

  @BuiltValueField(wireName: r'privacyAccepted')
  bool get privacyAccepted;

  @BuiltValueField(wireName: r'privacyPolicyVersion')
  String get privacyPolicyVersion;

  /// Required when Turnstile is enabled (prod, staging).
  @BuiltValueField(wireName: r'turnstileToken')
  String? get turnstileToken;

  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND (adds the origin-bound `@host #code` line).
  @BuiltValueField(wireName: r'smsFormat')
  PhoneOtpSendRequestSmsFormatEnum? get smsFormat;
  // enum smsFormatEnum {  DOMAIN_BOUND,  PLAIN,  };

  PhoneOtpSendRequest._();

  factory PhoneOtpSendRequest([void updates(PhoneOtpSendRequestBuilder b)]) =
      _$PhoneOtpSendRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhoneOtpSendRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhoneOtpSendRequest> get serializer =>
      _$PhoneOtpSendRequestSerializer();
}

class _$PhoneOtpSendRequestSerializer
    implements PrimitiveSerializer<PhoneOtpSendRequest> {
  @override
  final Iterable<Type> types = const [
    PhoneOtpSendRequest,
    _$PhoneOtpSendRequest
  ];

  @override
  final String wireName = r'PhoneOtpSendRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhoneOtpSendRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone';
    yield serializers.serialize(
      object.phone,
      specifiedType: const FullType(String),
    );
    yield r'privacyAccepted';
    yield serializers.serialize(
      object.privacyAccepted,
      specifiedType: const FullType(bool),
    );
    yield r'privacyPolicyVersion';
    yield serializers.serialize(
      object.privacyPolicyVersion,
      specifiedType: const FullType(String),
    );
    if (object.turnstileToken != null) {
      yield r'turnstileToken';
      yield serializers.serialize(
        object.turnstileToken,
        specifiedType: const FullType(String),
      );
    }
    if (object.smsFormat != null) {
      yield r'smsFormat';
      yield serializers.serialize(
        object.smsFormat,
        specifiedType: const FullType(PhoneOtpSendRequestSmsFormatEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PhoneOtpSendRequest object, {
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
    required PhoneOtpSendRequestBuilder result,
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
        case r'privacyAccepted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.privacyAccepted = valueDes;
          break;
        case r'privacyPolicyVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.privacyPolicyVersion = valueDes;
          break;
        case r'turnstileToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.turnstileToken = valueDes;
          break;
        case r'smsFormat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PhoneOtpSendRequestSmsFormatEnum),
          ) as PhoneOtpSendRequestSmsFormatEnum;
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
  PhoneOtpSendRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhoneOtpSendRequestBuilder();
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

class PhoneOtpSendRequestSmsFormatEnum extends EnumClass {
  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND (adds the origin-bound `@host #code` line).
  @BuiltValueEnumConst(wireName: r'DOMAIN_BOUND')
  static const PhoneOtpSendRequestSmsFormatEnum DOMAIN_BOUND =
      _$phoneOtpSendRequestSmsFormatEnum_DOMAIN_BOUND;

  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND (adds the origin-bound `@host #code` line).
  @BuiltValueEnumConst(wireName: r'PLAIN')
  static const PhoneOtpSendRequestSmsFormatEnum PLAIN =
      _$phoneOtpSendRequestSmsFormatEnum_PLAIN;

  /// Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND (adds the origin-bound `@host #code` line).
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const PhoneOtpSendRequestSmsFormatEnum unknownDefaultOpenApi =
      _$phoneOtpSendRequestSmsFormatEnum_unknownDefaultOpenApi;

  static Serializer<PhoneOtpSendRequestSmsFormatEnum> get serializer =>
      _$phoneOtpSendRequestSmsFormatEnumSerializer;

  const PhoneOtpSendRequestSmsFormatEnum._(String name) : super(name);

  static BuiltSet<PhoneOtpSendRequestSmsFormatEnum> get values =>
      _$phoneOtpSendRequestSmsFormatEnumValues;
  static PhoneOtpSendRequestSmsFormatEnum valueOf(String name) =>
      _$phoneOtpSendRequestSmsFormatEnumValueOf(name);
}
