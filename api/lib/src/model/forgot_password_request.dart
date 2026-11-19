//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'forgot_password_request.g.dart';

/// ForgotPasswordRequest
///
/// Properties:
/// * [email] - Legacy (pre-B516): the account email. Prefer identifier.
/// * [identifier] - Phone (+380…, 0…) or email, as typed by the user.
@BuiltValue()
abstract class ForgotPasswordRequest
    implements Built<ForgotPasswordRequest, ForgotPasswordRequestBuilder> {
  /// Legacy (pre-B516): the account email. Prefer identifier.
  @BuiltValueField(wireName: r'email')
  String? get email;

  /// Phone (+380…, 0…) or email, as typed by the user.
  @BuiltValueField(wireName: r'identifier')
  String? get identifier;

  ForgotPasswordRequest._();

  factory ForgotPasswordRequest(
      [void updates(ForgotPasswordRequestBuilder b)]) = _$ForgotPasswordRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ForgotPasswordRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ForgotPasswordRequest> get serializer =>
      _$ForgotPasswordRequestSerializer();
}

class _$ForgotPasswordRequestSerializer
    implements PrimitiveSerializer<ForgotPasswordRequest> {
  @override
  final Iterable<Type> types = const [
    ForgotPasswordRequest,
    _$ForgotPasswordRequest
  ];

  @override
  final String wireName = r'ForgotPasswordRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ForgotPasswordRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.email != null) {
      yield r'email';
      yield serializers.serialize(
        object.email,
        specifiedType: const FullType(String),
      );
    }
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
    ForgotPasswordRequest object, {
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
    required ForgotPasswordRequestBuilder result,
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
  ForgotPasswordRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ForgotPasswordRequestBuilder();
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
