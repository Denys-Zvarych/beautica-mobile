//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_target.g.dart';

/// NotificationTarget
///
/// Properties:
/// * [kind]
/// * [bookingId]
/// * [appointmentId]
/// * [salonId]
@BuiltValue()
abstract class NotificationTarget
    implements Built<NotificationTarget, NotificationTargetBuilder> {
  @BuiltValueField(wireName: r'kind')
  NotificationTargetKindEnum? get kind;
  // enum kindEnum {  BOOKING,  BOOKING_REVIEW,  SALON_TEAM,  NONE,  };

  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'appointmentId')
  String? get appointmentId;

  @BuiltValueField(wireName: r'salonId')
  String? get salonId;

  NotificationTarget._();

  factory NotificationTarget([void updates(NotificationTargetBuilder b)]) =
      _$NotificationTarget;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationTargetBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationTarget> get serializer =>
      _$NotificationTargetSerializer();
}

class _$NotificationTargetSerializer
    implements PrimitiveSerializer<NotificationTarget> {
  @override
  final Iterable<Type> types = const [NotificationTarget, _$NotificationTarget];

  @override
  final String wireName = r'NotificationTarget';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType(NotificationTargetKindEnum),
      );
    }
    if (object.bookingId != null) {
      yield r'bookingId';
      yield serializers.serialize(
        object.bookingId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.appointmentId != null) {
      yield r'appointmentId';
      yield serializers.serialize(
        object.appointmentId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.salonId != null) {
      yield r'salonId';
      yield serializers.serialize(
        object.salonId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationTarget object, {
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
    required NotificationTargetBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationTargetKindEnum),
          ) as NotificationTargetKindEnum;
          result.kind = valueDes;
          break;
        case r'bookingId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.bookingId = valueDes;
          break;
        case r'appointmentId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.appointmentId = valueDes;
          break;
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
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
  NotificationTarget deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationTargetBuilder();
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

class NotificationTargetKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'BOOKING')
  static const NotificationTargetKindEnum BOOKING =
      _$notificationTargetKindEnum_BOOKING;
  @BuiltValueEnumConst(wireName: r'BOOKING_REVIEW')
  static const NotificationTargetKindEnum BOOKING_REVIEW =
      _$notificationTargetKindEnum_BOOKING_REVIEW;
  @BuiltValueEnumConst(wireName: r'SALON_TEAM')
  static const NotificationTargetKindEnum SALON_TEAM =
      _$notificationTargetKindEnum_SALON_TEAM;
  @BuiltValueEnumConst(wireName: r'NONE')
  static const NotificationTargetKindEnum NONE =
      _$notificationTargetKindEnum_NONE;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NotificationTargetKindEnum unknownDefaultOpenApi =
      _$notificationTargetKindEnum_unknownDefaultOpenApi;

  static Serializer<NotificationTargetKindEnum> get serializer =>
      _$notificationTargetKindEnumSerializer;

  const NotificationTargetKindEnum._(String name) : super(name);

  static BuiltSet<NotificationTargetKindEnum> get values =>
      _$notificationTargetKindEnumValues;
  static NotificationTargetKindEnum valueOf(String name) =>
      _$notificationTargetKindEnumValueOf(name);
}
