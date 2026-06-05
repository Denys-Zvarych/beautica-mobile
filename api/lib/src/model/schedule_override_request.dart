//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/work_interval_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_override_request.g.dart';

/// ScheduleOverrideRequest
///
/// Properties:
/// * [date]
/// * [kind]
/// * [reason]
/// * [note]
/// * [intervals]
/// * [kindConsistent]
@BuiltValue()
abstract class ScheduleOverrideRequest
    implements Built<ScheduleOverrideRequest, ScheduleOverrideRequestBuilder> {
  @BuiltValueField(wireName: r'date')
  Date get date;

  @BuiltValueField(wireName: r'kind')
  ScheduleOverrideRequestKindEnum get kind;
  // enum kindEnum {  DAY_OFF,  CUSTOM_HOURS,  };

  @BuiltValueField(wireName: r'reason')
  ScheduleOverrideRequestReasonEnum? get reason;
  // enum reasonEnum {  VACATION,  HOLIDAY,  SICK_DAY,  OTHER,  };

  @BuiltValueField(wireName: r'note')
  String? get note;

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

  @BuiltValueField(wireName: r'kindConsistent')
  bool? get kindConsistent;

  ScheduleOverrideRequest._();

  factory ScheduleOverrideRequest(
          [void updates(ScheduleOverrideRequestBuilder b)]) =
      _$ScheduleOverrideRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScheduleOverrideRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScheduleOverrideRequest> get serializer =>
      _$ScheduleOverrideRequestSerializer();
}

class _$ScheduleOverrideRequestSerializer
    implements PrimitiveSerializer<ScheduleOverrideRequest> {
  @override
  final Iterable<Type> types = const [
    ScheduleOverrideRequest,
    _$ScheduleOverrideRequest
  ];

  @override
  final String wireName = r'ScheduleOverrideRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScheduleOverrideRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'date';
    yield serializers.serialize(
      object.date,
      specifiedType: const FullType(Date),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(ScheduleOverrideRequestKindEnum),
    );
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(ScheduleOverrideRequestReasonEnum),
      );
    }
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType(String),
      );
    }
    if (object.intervals != null) {
      yield r'intervals';
      yield serializers.serialize(
        object.intervals,
        specifiedType: const FullType(BuiltList, [FullType(WorkIntervalDto)]),
      );
    }
    if (object.kindConsistent != null) {
      yield r'kindConsistent';
      yield serializers.serialize(
        object.kindConsistent,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ScheduleOverrideRequest object, {
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
    required ScheduleOverrideRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ScheduleOverrideRequestKindEnum),
          ) as ScheduleOverrideRequestKindEnum;
          result.kind = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ScheduleOverrideRequestReasonEnum),
          ) as ScheduleOverrideRequestReasonEnum;
          result.reason = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.note = valueDes;
          break;
        case r'intervals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(WorkIntervalDto)]),
          ) as BuiltList<WorkIntervalDto>;
          result.intervals.replace(valueDes);
          break;
        case r'kindConsistent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.kindConsistent = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScheduleOverrideRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScheduleOverrideRequestBuilder();
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

class ScheduleOverrideRequestKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'DAY_OFF')
  static const ScheduleOverrideRequestKindEnum DAY_OFF =
      _$scheduleOverrideRequestKindEnum_DAY_OFF;
  @BuiltValueEnumConst(wireName: r'CUSTOM_HOURS')
  static const ScheduleOverrideRequestKindEnum CUSTOM_HOURS =
      _$scheduleOverrideRequestKindEnum_CUSTOM_HOURS;

  static Serializer<ScheduleOverrideRequestKindEnum> get serializer =>
      _$scheduleOverrideRequestKindEnumSerializer;

  const ScheduleOverrideRequestKindEnum._(String name) : super(name);

  static BuiltSet<ScheduleOverrideRequestKindEnum> get values =>
      _$scheduleOverrideRequestKindEnumValues;
  static ScheduleOverrideRequestKindEnum valueOf(String name) =>
      _$scheduleOverrideRequestKindEnumValueOf(name);
}

class ScheduleOverrideRequestReasonEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'VACATION')
  static const ScheduleOverrideRequestReasonEnum VACATION =
      _$scheduleOverrideRequestReasonEnum_VACATION;
  @BuiltValueEnumConst(wireName: r'HOLIDAY')
  static const ScheduleOverrideRequestReasonEnum HOLIDAY =
      _$scheduleOverrideRequestReasonEnum_HOLIDAY;
  @BuiltValueEnumConst(wireName: r'SICK_DAY')
  static const ScheduleOverrideRequestReasonEnum SICK_DAY =
      _$scheduleOverrideRequestReasonEnum_SICK_DAY;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const ScheduleOverrideRequestReasonEnum OTHER =
      _$scheduleOverrideRequestReasonEnum_OTHER;

  static Serializer<ScheduleOverrideRequestReasonEnum> get serializer =>
      _$scheduleOverrideRequestReasonEnumSerializer;

  const ScheduleOverrideRequestReasonEnum._(String name) : super(name);

  static BuiltSet<ScheduleOverrideRequestReasonEnum> get values =>
      _$scheduleOverrideRequestReasonEnumValues;
  static ScheduleOverrideRequestReasonEnum valueOf(String name) =>
      _$scheduleOverrideRequestReasonEnumValueOf(name);
}
