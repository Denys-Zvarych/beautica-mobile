//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'resend_verification_request.g.dart';

/// ResendVerificationRequest
///
/// Properties:
/// * [email]
@BuiltValue()
abstract class ResendVerificationRequest
    implements
        Built<ResendVerificationRequest, ResendVerificationRequestBuilder> {
  @BuiltValueField(wireName: r'email')
  String get email;

  ResendVerificationRequest._();

  factory ResendVerificationRequest(
          [void updates(ResendVerificationRequestBuilder b)]) =
      _$ResendVerificationRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResendVerificationRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResendVerificationRequest> get serializer =>
      _$ResendVerificationRequestSerializer();
}

class _$ResendVerificationRequestSerializer
    implements PrimitiveSerializer<ResendVerificationRequest> {
  @override
  final Iterable<Type> types = const [
    ResendVerificationRequest,
    _$ResendVerificationRequest
  ];

  @override
  final String wireName = r'ResendVerificationRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResendVerificationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'email';
    yield serializers.serialize(
      object.email,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ResendVerificationRequest object, {
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
    required ResendVerificationRequestBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ResendVerificationRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResendVerificationRequestBuilder();
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
