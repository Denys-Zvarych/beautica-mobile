//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/notification_params.dart';
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/notification_target.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_response.g.dart';

/// NotificationResponse
///
/// Properties:
/// * [id]
/// * [type]
/// * [createdAt]
/// * [read]
/// * [target]
/// * [params]
@BuiltValue()
abstract class NotificationResponse
    implements Built<NotificationResponse, NotificationResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'type')
  NotificationResponseTypeEnum? get type;
  // enum typeEnum {  BOOKING_CREATED,  BOOKING_CANCELLED_BY_CLIENT,  BOOKING_DECLINED,  BOOKING_NOT_COMPLETED,  BOOKING_RESCHEDULED,  REVIEW_REQUESTED,  BOOKING_CANCELLED_SALON_CLOSED,  BOOKING_CANCELLED_MASTER_REMOVED,  REVIEW_RECEIVED,  INVITE_ACCEPTED,  };

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  @BuiltValueField(wireName: r'read')
  bool? get read;

  @BuiltValueField(wireName: r'target')
  NotificationTarget? get target;

  @BuiltValueField(wireName: r'params')
  NotificationParams? get params;

  NotificationResponse._();

  factory NotificationResponse([void updates(NotificationResponseBuilder b)]) =
      _$NotificationResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationResponse> get serializer =>
      _$NotificationResponseSerializer();
}

class _$NotificationResponseSerializer
    implements PrimitiveSerializer<NotificationResponse> {
  @override
  final Iterable<Type> types = const [
    NotificationResponse,
    _$NotificationResponse
  ];

  @override
  final String wireName = r'NotificationResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.type != null) {
      yield r'type';
      yield serializers.serialize(
        object.type,
        specifiedType: const FullType(NotificationResponseTypeEnum),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.read != null) {
      yield r'read';
      yield serializers.serialize(
        object.read,
        specifiedType: const FullType(bool),
      );
    }
    if (object.target != null) {
      yield r'target';
      yield serializers.serialize(
        object.target,
        specifiedType: const FullType(NotificationTarget),
      );
    }
    if (object.params != null) {
      yield r'params';
      yield serializers.serialize(
        object.params,
        specifiedType: const FullType(NotificationParams),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationResponse object, {
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
    required NotificationResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationResponseTypeEnum),
          ) as NotificationResponseTypeEnum;
          result.type = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'read':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.read = valueDes;
          break;
        case r'target':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationTarget),
          ) as NotificationTarget;
          result.target.replace(valueDes);
          break;
        case r'params':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationParams),
          ) as NotificationParams;
          result.params.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationResponseBuilder();
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

class NotificationResponseTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'BOOKING_CREATED')
  static const NotificationResponseTypeEnum BOOKING_CREATED =
      _$notificationResponseTypeEnum_BOOKING_CREATED;
  @BuiltValueEnumConst(wireName: r'BOOKING_CANCELLED_BY_CLIENT')
  static const NotificationResponseTypeEnum BOOKING_CANCELLED_BY_CLIENT =
      _$notificationResponseTypeEnum_BOOKING_CANCELLED_BY_CLIENT;
  @BuiltValueEnumConst(wireName: r'BOOKING_DECLINED')
  static const NotificationResponseTypeEnum BOOKING_DECLINED =
      _$notificationResponseTypeEnum_BOOKING_DECLINED;
  @BuiltValueEnumConst(wireName: r'BOOKING_NOT_COMPLETED')
  static const NotificationResponseTypeEnum BOOKING_NOT_COMPLETED =
      _$notificationResponseTypeEnum_BOOKING_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'BOOKING_RESCHEDULED')
  static const NotificationResponseTypeEnum BOOKING_RESCHEDULED =
      _$notificationResponseTypeEnum_BOOKING_RESCHEDULED;
  @BuiltValueEnumConst(wireName: r'REVIEW_REQUESTED')
  static const NotificationResponseTypeEnum REVIEW_REQUESTED =
      _$notificationResponseTypeEnum_REVIEW_REQUESTED;
  @BuiltValueEnumConst(wireName: r'BOOKING_CANCELLED_SALON_CLOSED')
  static const NotificationResponseTypeEnum BOOKING_CANCELLED_SALON_CLOSED =
      _$notificationResponseTypeEnum_BOOKING_CANCELLED_SALON_CLOSED;
  @BuiltValueEnumConst(wireName: r'BOOKING_CANCELLED_MASTER_REMOVED')
  static const NotificationResponseTypeEnum BOOKING_CANCELLED_MASTER_REMOVED =
      _$notificationResponseTypeEnum_BOOKING_CANCELLED_MASTER_REMOVED;
  @BuiltValueEnumConst(wireName: r'REVIEW_RECEIVED')
  static const NotificationResponseTypeEnum REVIEW_RECEIVED =
      _$notificationResponseTypeEnum_REVIEW_RECEIVED;
  @BuiltValueEnumConst(wireName: r'INVITE_ACCEPTED')
  static const NotificationResponseTypeEnum INVITE_ACCEPTED =
      _$notificationResponseTypeEnum_INVITE_ACCEPTED;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NotificationResponseTypeEnum unknownDefaultOpenApi =
      _$notificationResponseTypeEnum_unknownDefaultOpenApi;

  static Serializer<NotificationResponseTypeEnum> get serializer =>
      _$notificationResponseTypeEnumSerializer;

  const NotificationResponseTypeEnum._(String name) : super(name);

  static BuiltSet<NotificationResponseTypeEnum> get values =>
      _$notificationResponseTypeEnumValues;
  static NotificationResponseTypeEnum valueOf(String name) =>
      _$notificationResponseTypeEnumValueOf(name);
}
