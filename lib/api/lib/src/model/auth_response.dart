//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'auth_response.g.dart';

/// AuthResponse
///
/// Properties:
/// * [accessToken]
/// * [refreshToken]
/// * [tokenType]
/// * [userId]
/// * [email]
/// * [role]
/// * [salonId]
@BuiltValue()
abstract class AuthResponse
    implements Built<AuthResponse, AuthResponseBuilder> {
  @BuiltValueField(wireName: r'accessToken')
  String? get accessToken;

  @BuiltValueField(wireName: r'refreshToken')
  String? get refreshToken;

  @BuiltValueField(wireName: r'tokenType')
  String? get tokenType;

  @BuiltValueField(wireName: r'userId')
  String? get userId;

  @BuiltValueField(wireName: r'email')
  String? get email;

  @BuiltValueField(wireName: r'role')
  AuthResponseRoleEnum? get role;
  // enum roleEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  @BuiltValueField(wireName: r'salonId')
  String? get salonId;

  AuthResponse._();

  factory AuthResponse([void updates(AuthResponseBuilder b)]) = _$AuthResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AuthResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AuthResponse> get serializer => _$AuthResponseSerializer();
}

class _$AuthResponseSerializer implements PrimitiveSerializer<AuthResponse> {
  @override
  final Iterable<Type> types = const [AuthResponse, _$AuthResponse];

  @override
  final String wireName = r'AuthResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AuthResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.accessToken != null) {
      yield r'accessToken';
      yield serializers.serialize(
        object.accessToken,
        specifiedType: const FullType(String),
      );
    }
    if (object.refreshToken != null) {
      yield r'refreshToken';
      yield serializers.serialize(
        object.refreshToken,
        specifiedType: const FullType(String),
      );
    }
    if (object.tokenType != null) {
      yield r'tokenType';
      yield serializers.serialize(
        object.tokenType,
        specifiedType: const FullType(String),
      );
    }
    if (object.userId != null) {
      yield r'userId';
      yield serializers.serialize(
        object.userId,
        specifiedType: const FullType(String),
      );
    }
    if (object.email != null) {
      yield r'email';
      yield serializers.serialize(
        object.email,
        specifiedType: const FullType(String),
      );
    }
    if (object.role != null) {
      yield r'role';
      yield serializers.serialize(
        object.role,
        specifiedType: const FullType(AuthResponseRoleEnum),
      );
    }
    if (object.salonId != null) {
      yield r'salonId';
      yield serializers.serialize(
        object.salonId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AuthResponse object, {
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
    required AuthResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accessToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accessToken = valueDes;
          break;
        case r'refreshToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.refreshToken = valueDes;
          break;
        case r'tokenType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.tokenType = valueDes;
          break;
        case r'userId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'email':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.email = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AuthResponseRoleEnum),
          ) as AuthResponseRoleEnum;
          result.role = valueDes;
          break;
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.salonId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AuthResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AuthResponseBuilder();
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

class AuthResponseRoleEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const AuthResponseRoleEnum CLIENT = _$authResponseRoleEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const AuthResponseRoleEnum SALON_OWNER =
      _$authResponseRoleEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const AuthResponseRoleEnum SALON_ADMIN =
      _$authResponseRoleEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const AuthResponseRoleEnum SALON_MASTER =
      _$authResponseRoleEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const AuthResponseRoleEnum INDEPENDENT_MASTER =
      _$authResponseRoleEnum_INDEPENDENT_MASTER;

  static Serializer<AuthResponseRoleEnum> get serializer =>
      _$authResponseRoleEnumSerializer;

  const AuthResponseRoleEnum._(String name) : super(name);

  static BuiltSet<AuthResponseRoleEnum> get values =>
      _$authResponseRoleEnumValues;
  static AuthResponseRoleEnum valueOf(String name) =>
      _$authResponseRoleEnumValueOf(name);
}
