//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'invite_preview_response.g.dart';

/// InvitePreviewResponse
///
/// Properties:
/// * [invitedEmail]
/// * [role]
/// * [expiresAt]
@BuiltValue()
abstract class InvitePreviewResponse
    implements Built<InvitePreviewResponse, InvitePreviewResponseBuilder> {
  @BuiltValueField(wireName: r'invitedEmail')
  String? get invitedEmail;

  @BuiltValueField(wireName: r'role')
  InvitePreviewResponseRoleEnum? get role;
  // enum roleEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  InvitePreviewResponse._();

  factory InvitePreviewResponse(
      [void updates(InvitePreviewResponseBuilder b)]) = _$InvitePreviewResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InvitePreviewResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InvitePreviewResponse> get serializer =>
      _$InvitePreviewResponseSerializer();
}

class _$InvitePreviewResponseSerializer
    implements PrimitiveSerializer<InvitePreviewResponse> {
  @override
  final Iterable<Type> types = const [
    InvitePreviewResponse,
    _$InvitePreviewResponse
  ];

  @override
  final String wireName = r'InvitePreviewResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InvitePreviewResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.invitedEmail != null) {
      yield r'invitedEmail';
      yield serializers.serialize(
        object.invitedEmail,
        specifiedType: const FullType(String),
      );
    }
    if (object.role != null) {
      yield r'role';
      yield serializers.serialize(
        object.role,
        specifiedType: const FullType(InvitePreviewResponseRoleEnum),
      );
    }
    if (object.expiresAt != null) {
      yield r'expiresAt';
      yield serializers.serialize(
        object.expiresAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InvitePreviewResponse object, {
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
    required InvitePreviewResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'invitedEmail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.invitedEmail = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InvitePreviewResponseRoleEnum),
          ) as InvitePreviewResponseRoleEnum;
          result.role = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InvitePreviewResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InvitePreviewResponseBuilder();
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

class InvitePreviewResponseRoleEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const InvitePreviewResponseRoleEnum CLIENT =
      _$invitePreviewResponseRoleEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const InvitePreviewResponseRoleEnum SALON_OWNER =
      _$invitePreviewResponseRoleEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const InvitePreviewResponseRoleEnum SALON_ADMIN =
      _$invitePreviewResponseRoleEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const InvitePreviewResponseRoleEnum SALON_MASTER =
      _$invitePreviewResponseRoleEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const InvitePreviewResponseRoleEnum INDEPENDENT_MASTER =
      _$invitePreviewResponseRoleEnum_INDEPENDENT_MASTER;

  static Serializer<InvitePreviewResponseRoleEnum> get serializer =>
      _$invitePreviewResponseRoleEnumSerializer;

  const InvitePreviewResponseRoleEnum._(String name) : super(name);

  static BuiltSet<InvitePreviewResponseRoleEnum> get values =>
      _$invitePreviewResponseRoleEnumValues;
  static InvitePreviewResponseRoleEnum valueOf(String name) =>
      _$invitePreviewResponseRoleEnumValueOf(name);
}
