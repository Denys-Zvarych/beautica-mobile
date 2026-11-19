//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_email_verify_request.g.dart';

/// NotificationEmailVerifyRequest
///
/// Properties:
/// * [email]
/// * [code]
/// * [currentPassword]
@BuiltValue()
abstract class NotificationEmailVerifyRequest
    implements
        Built<NotificationEmailVerifyRequest,
            NotificationEmailVerifyRequestBuilder> {
  @BuiltValueField(wireName: r'email')
  String get email;

  @BuiltValueField(wireName: r'code')
  String get code;

  @BuiltValueField(wireName: r'currentPassword')
  String? get currentPassword;

  NotificationEmailVerifyRequest._();

  factory NotificationEmailVerifyRequest(
          [void updates(NotificationEmailVerifyRequestBuilder b)]) =
      _$NotificationEmailVerifyRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationEmailVerifyRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationEmailVerifyRequest> get serializer =>
      _$NotificationEmailVerifyRequestSerializer();
}

class _$NotificationEmailVerifyRequestSerializer
    implements PrimitiveSerializer<NotificationEmailVerifyRequest> {
  @override
  final Iterable<Type> types = const [
    NotificationEmailVerifyRequest,
    _$NotificationEmailVerifyRequest
  ];

  @override
  final String wireName = r'NotificationEmailVerifyRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationEmailVerifyRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'email';
    yield serializers.serialize(
      object.email,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    if (object.currentPassword != null) {
      yield r'currentPassword';
      yield serializers.serialize(
        object.currentPassword,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationEmailVerifyRequest object, {
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
    required NotificationEmailVerifyRequestBuilder result,
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
        case r'currentPassword':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.currentPassword = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationEmailVerifyRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationEmailVerifyRequestBuilder();
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
