//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'invite_request.g.dart';

/// InviteRequest
///
/// Properties:
/// * [email]
/// * [role]
/// * [roleAllowed]
@BuiltValue()
abstract class InviteRequest
    implements Built<InviteRequest, InviteRequestBuilder> {
  @BuiltValueField(wireName: r'email')
  String get email;

  @BuiltValueField(wireName: r'role')
  InviteRequestRoleEnum? get role;
  // enum roleEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  @BuiltValueField(wireName: r'roleAllowed')
  bool? get roleAllowed;

  InviteRequest._();

  factory InviteRequest([void updates(InviteRequestBuilder b)]) =
      _$InviteRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InviteRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InviteRequest> get serializer =>
      _$InviteRequestSerializer();
}

class _$InviteRequestSerializer implements PrimitiveSerializer<InviteRequest> {
  @override
  final Iterable<Type> types = const [InviteRequest, _$InviteRequest];

  @override
  final String wireName = r'InviteRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InviteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'email';
    yield serializers.serialize(
      object.email,
      specifiedType: const FullType(String),
    );
    if (object.role != null) {
      yield r'role';
      yield serializers.serialize(
        object.role,
        specifiedType: const FullType(InviteRequestRoleEnum),
      );
    }
    if (object.roleAllowed != null) {
      yield r'roleAllowed';
      yield serializers.serialize(
        object.roleAllowed,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InviteRequest object, {
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
    required InviteRequestBuilder result,
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
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InviteRequestRoleEnum),
          ) as InviteRequestRoleEnum;
          result.role = valueDes;
          break;
        case r'roleAllowed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.roleAllowed = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InviteRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InviteRequestBuilder();
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

class InviteRequestRoleEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const InviteRequestRoleEnum CLIENT = _$inviteRequestRoleEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const InviteRequestRoleEnum SALON_OWNER =
      _$inviteRequestRoleEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const InviteRequestRoleEnum SALON_ADMIN =
      _$inviteRequestRoleEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const InviteRequestRoleEnum SALON_MASTER =
      _$inviteRequestRoleEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const InviteRequestRoleEnum INDEPENDENT_MASTER =
      _$inviteRequestRoleEnum_INDEPENDENT_MASTER;

  static Serializer<InviteRequestRoleEnum> get serializer =>
      _$inviteRequestRoleEnumSerializer;

  const InviteRequestRoleEnum._(String name) : super(name);

  static BuiltSet<InviteRequestRoleEnum> get values =>
      _$inviteRequestRoleEnumValues;
  static InviteRequestRoleEnum valueOf(String name) =>
      _$inviteRequestRoleEnumValueOf(name);
}
