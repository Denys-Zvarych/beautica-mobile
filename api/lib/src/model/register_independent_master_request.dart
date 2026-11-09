//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'register_independent_master_request.g.dart';

/// RegisterIndependentMasterRequest
///
/// Properties:
/// * [email]
/// * [password]
/// * [firstName]
/// * [lastName]
/// * [phoneNumber]
/// * [termsAccepted]
/// * [termsVersion]
/// * [privacyPolicyVersion]
@BuiltValue()
abstract class RegisterIndependentMasterRequest
    implements
        Built<RegisterIndependentMasterRequest,
            RegisterIndependentMasterRequestBuilder> {
  @BuiltValueField(wireName: r'email')
  String get email;

  @BuiltValueField(wireName: r'password')
  String get password;

  @BuiltValueField(wireName: r'firstName')
  String get firstName;

  @BuiltValueField(wireName: r'lastName')
  String get lastName;

  @BuiltValueField(wireName: r'phoneNumber')
  String get phoneNumber;

  @BuiltValueField(wireName: r'termsAccepted')
  bool? get termsAccepted;

  @BuiltValueField(wireName: r'termsVersion')
  String? get termsVersion;

  @BuiltValueField(wireName: r'privacyPolicyVersion')
  String? get privacyPolicyVersion;

  RegisterIndependentMasterRequest._();

  factory RegisterIndependentMasterRequest(
          [void updates(RegisterIndependentMasterRequestBuilder b)]) =
      _$RegisterIndependentMasterRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegisterIndependentMasterRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegisterIndependentMasterRequest> get serializer =>
      _$RegisterIndependentMasterRequestSerializer();
}

class _$RegisterIndependentMasterRequestSerializer
    implements PrimitiveSerializer<RegisterIndependentMasterRequest> {
  @override
  final Iterable<Type> types = const [
    RegisterIndependentMasterRequest,
    _$RegisterIndependentMasterRequest
  ];

  @override
  final String wireName = r'RegisterIndependentMasterRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegisterIndependentMasterRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'email';
    yield serializers.serialize(
      object.email,
      specifiedType: const FullType(String),
    );
    yield r'password';
    yield serializers.serialize(
      object.password,
      specifiedType: const FullType(String),
    );
    yield r'firstName';
    yield serializers.serialize(
      object.firstName,
      specifiedType: const FullType(String),
    );
    yield r'lastName';
    yield serializers.serialize(
      object.lastName,
      specifiedType: const FullType(String),
    );
    yield r'phoneNumber';
    yield serializers.serialize(
      object.phoneNumber,
      specifiedType: const FullType(String),
    );
    if (object.termsAccepted != null) {
      yield r'termsAccepted';
      yield serializers.serialize(
        object.termsAccepted,
        specifiedType: const FullType(bool),
      );
    }
    if (object.termsVersion != null) {
      yield r'termsVersion';
      yield serializers.serialize(
        object.termsVersion,
        specifiedType: const FullType(String),
      );
    }
    if (object.privacyPolicyVersion != null) {
      yield r'privacyPolicyVersion';
      yield serializers.serialize(
        object.privacyPolicyVersion,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RegisterIndependentMasterRequest object, {
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
    required RegisterIndependentMasterRequestBuilder result,
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
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.password = valueDes;
          break;
        case r'firstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.firstName = valueDes;
          break;
        case r'lastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastName = valueDes;
          break;
        case r'phoneNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phoneNumber = valueDes;
          break;
        case r'termsAccepted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.termsAccepted = valueDes;
          break;
        case r'termsVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.termsVersion = valueDes;
          break;
        case r'privacyPolicyVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.privacyPolicyVersion = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegisterIndependentMasterRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegisterIndependentMasterRequestBuilder();
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
