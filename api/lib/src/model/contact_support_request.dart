//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'contact_support_request.g.dart';

/// ContactSupportRequest
///
/// Properties:
/// * [message]
/// * [subject]
@BuiltValue()
abstract class ContactSupportRequest
    implements Built<ContactSupportRequest, ContactSupportRequestBuilder> {
  @BuiltValueField(wireName: r'message')
  String get message;

  @BuiltValueField(wireName: r'subject')
  String? get subject;

  ContactSupportRequest._();

  factory ContactSupportRequest(
      [void updates(ContactSupportRequestBuilder b)]) = _$ContactSupportRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ContactSupportRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ContactSupportRequest> get serializer =>
      _$ContactSupportRequestSerializer();
}

class _$ContactSupportRequestSerializer
    implements PrimitiveSerializer<ContactSupportRequest> {
  @override
  final Iterable<Type> types = const [
    ContactSupportRequest,
    _$ContactSupportRequest
  ];

  @override
  final String wireName = r'ContactSupportRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ContactSupportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'message';
    yield serializers.serialize(
      object.message,
      specifiedType: const FullType(String),
    );
    if (object.subject != null) {
      yield r'subject';
      yield serializers.serialize(
        object.subject,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ContactSupportRequest object, {
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
    required ContactSupportRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'subject':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.subject = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ContactSupportRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ContactSupportRequestBuilder();
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
