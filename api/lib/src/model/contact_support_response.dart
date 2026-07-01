//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'contact_support_response.g.dart';

/// ContactSupportResponse
///
/// Properties:
/// * [message]
@BuiltValue()
abstract class ContactSupportResponse
    implements Built<ContactSupportResponse, ContactSupportResponseBuilder> {
  @BuiltValueField(wireName: r'message')
  String? get message;

  ContactSupportResponse._();

  factory ContactSupportResponse(
          [void updates(ContactSupportResponseBuilder b)]) =
      _$ContactSupportResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ContactSupportResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ContactSupportResponse> get serializer =>
      _$ContactSupportResponseSerializer();
}

class _$ContactSupportResponseSerializer
    implements PrimitiveSerializer<ContactSupportResponse> {
  @override
  final Iterable<Type> types = const [
    ContactSupportResponse,
    _$ContactSupportResponse
  ];

  @override
  final String wireName = r'ContactSupportResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ContactSupportResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ContactSupportResponse object, {
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
    required ContactSupportResponseBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ContactSupportResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ContactSupportResponseBuilder();
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
