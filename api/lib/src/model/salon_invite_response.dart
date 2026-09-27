//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_invite_response.g.dart';

/// SalonInviteResponse
///
/// Properties:
/// * [inviteId]
/// * [recipientEmail]
/// * [role]
/// * [status]
/// * [createdAt]
/// * [expiresAt]
@BuiltValue()
abstract class SalonInviteResponse
    implements Built<SalonInviteResponse, SalonInviteResponseBuilder> {
  @BuiltValueField(wireName: r'inviteId')
  String? get inviteId;

  @BuiltValueField(wireName: r'recipientEmail')
  String? get recipientEmail;

  @BuiltValueField(wireName: r'role')
  String? get role;

  @BuiltValueField(wireName: r'status')
  String? get status;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  SalonInviteResponse._();

  factory SalonInviteResponse([void updates(SalonInviteResponseBuilder b)]) =
      _$SalonInviteResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonInviteResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonInviteResponse> get serializer =>
      _$SalonInviteResponseSerializer();
}

class _$SalonInviteResponseSerializer
    implements PrimitiveSerializer<SalonInviteResponse> {
  @override
  final Iterable<Type> types = const [
    SalonInviteResponse,
    _$SalonInviteResponse
  ];

  @override
  final String wireName = r'SalonInviteResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonInviteResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.inviteId != null) {
      yield r'inviteId';
      yield serializers.serialize(
        object.inviteId,
        specifiedType: const FullType(String),
      );
    }
    if (object.recipientEmail != null) {
      yield r'recipientEmail';
      yield serializers.serialize(
        object.recipientEmail,
        specifiedType: const FullType(String),
      );
    }
    if (object.role != null) {
      yield r'role';
      yield serializers.serialize(
        object.role,
        specifiedType: const FullType(String),
      );
    }
    if (object.status != null) {
      yield r'status';
      yield serializers.serialize(
        object.status,
        specifiedType: const FullType(String),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
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
    SalonInviteResponse object, {
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
    required SalonInviteResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'inviteId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.inviteId = valueDes;
          break;
        case r'recipientEmail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.recipientEmail = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.role = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
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
  SalonInviteResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonInviteResponseBuilder();
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
