//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_params.g.dart';

/// NotificationParams
///
/// Properties:
/// * [counterpartName]
/// * [serviceName]
/// * [serviceCount]
/// * [startsAt]
/// * [salonName]
/// * [subjectName]
/// * [subjectRole]
@BuiltValue()
abstract class NotificationParams
    implements Built<NotificationParams, NotificationParamsBuilder> {
  @BuiltValueField(wireName: r'counterpartName')
  String? get counterpartName;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'serviceCount')
  int? get serviceCount;

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'salonName')
  String? get salonName;

  @BuiltValueField(wireName: r'subjectName')
  String? get subjectName;

  @BuiltValueField(wireName: r'subjectRole')
  NotificationParamsSubjectRoleEnum? get subjectRole;
  // enum subjectRoleEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  NotificationParams._();

  factory NotificationParams([void updates(NotificationParamsBuilder b)]) =
      _$NotificationParams;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationParamsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationParams> get serializer =>
      _$NotificationParamsSerializer();
}

class _$NotificationParamsSerializer
    implements PrimitiveSerializer<NotificationParams> {
  @override
  final Iterable<Type> types = const [NotificationParams, _$NotificationParams];

  @override
  final String wireName = r'NotificationParams';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationParams object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.counterpartName != null) {
      yield r'counterpartName';
      yield serializers.serialize(
        object.counterpartName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.serviceCount != null) {
      yield r'serviceCount';
      yield serializers.serialize(
        object.serviceCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.salonName != null) {
      yield r'salonName';
      yield serializers.serialize(
        object.salonName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.subjectName != null) {
      yield r'subjectName';
      yield serializers.serialize(
        object.subjectName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.subjectRole != null) {
      yield r'subjectRole';
      yield serializers.serialize(
        object.subjectRole,
        specifiedType:
            const FullType.nullable(NotificationParamsSubjectRoleEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationParams object, {
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
    required NotificationParamsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'counterpartName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.counterpartName = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.serviceName = valueDes;
          break;
        case r'serviceCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.serviceCount = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.startsAt = valueDes;
          break;
        case r'salonName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.salonName = valueDes;
          break;
        case r'subjectName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.subjectName = valueDes;
          break;
        case r'subjectRole':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(NotificationParamsSubjectRoleEnum),
          ) as NotificationParamsSubjectRoleEnum?;
          if (valueDes == null) continue;
          result.subjectRole = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationParams deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationParamsBuilder();
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

class NotificationParamsSubjectRoleEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const NotificationParamsSubjectRoleEnum CLIENT =
      _$notificationParamsSubjectRoleEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const NotificationParamsSubjectRoleEnum SALON_OWNER =
      _$notificationParamsSubjectRoleEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const NotificationParamsSubjectRoleEnum SALON_ADMIN =
      _$notificationParamsSubjectRoleEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const NotificationParamsSubjectRoleEnum SALON_MASTER =
      _$notificationParamsSubjectRoleEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const NotificationParamsSubjectRoleEnum INDEPENDENT_MASTER =
      _$notificationParamsSubjectRoleEnum_INDEPENDENT_MASTER;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NotificationParamsSubjectRoleEnum unknownDefaultOpenApi =
      _$notificationParamsSubjectRoleEnum_unknownDefaultOpenApi;

  static Serializer<NotificationParamsSubjectRoleEnum> get serializer =>
      _$notificationParamsSubjectRoleEnumSerializer;

  const NotificationParamsSubjectRoleEnum._(String name) : super(name);

  static BuiltSet<NotificationParamsSubjectRoleEnum> get values =>
      _$notificationParamsSubjectRoleEnumValues;
  static NotificationParamsSubjectRoleEnum valueOf(String name) =>
      _$notificationParamsSubjectRoleEnumValueOf(name);
}
