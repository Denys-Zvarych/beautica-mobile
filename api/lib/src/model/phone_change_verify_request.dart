//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phone_change_verify_request.g.dart';

/// PhoneChangeVerifyRequest
///
/// Properties:
/// * [phone]
/// * [code]
/// * [currentPassword]
@BuiltValue()
abstract class PhoneChangeVerifyRequest
    implements
        Built<PhoneChangeVerifyRequest, PhoneChangeVerifyRequestBuilder> {
  @BuiltValueField(wireName: r'phone')
  String get phone;

  @BuiltValueField(wireName: r'code')
  String get code;

  @BuiltValueField(wireName: r'currentPassword')
  String? get currentPassword;

  PhoneChangeVerifyRequest._();

  factory PhoneChangeVerifyRequest(
          [void updates(PhoneChangeVerifyRequestBuilder b)]) =
      _$PhoneChangeVerifyRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhoneChangeVerifyRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhoneChangeVerifyRequest> get serializer =>
      _$PhoneChangeVerifyRequestSerializer();
}

class _$PhoneChangeVerifyRequestSerializer
    implements PrimitiveSerializer<PhoneChangeVerifyRequest> {
  @override
  final Iterable<Type> types = const [
    PhoneChangeVerifyRequest,
    _$PhoneChangeVerifyRequest
  ];

  @override
  final String wireName = r'PhoneChangeVerifyRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhoneChangeVerifyRequest object, {
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
    PhoneChangeVerifyRequest object, {
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
    required PhoneChangeVerifyRequestBuilder result,
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
  PhoneChangeVerifyRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhoneChangeVerifyRequestBuilder();
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
