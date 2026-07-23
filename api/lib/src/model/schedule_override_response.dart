//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/work_interval_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_override_response.g.dart';

/// ScheduleOverrideResponse
///
/// Properties:
/// * [date]
/// * [kind]
/// * [mode]
/// * [intervals]
/// * [times]
@BuiltValue()
abstract class ScheduleOverrideResponse
    implements
        Built<ScheduleOverrideResponse, ScheduleOverrideResponseBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'kind')
  ScheduleOverrideResponseKindEnum? get kind;
  // enum kindEnum {  DAY_OFF,  CUSTOM_HOURS,  };

  @BuiltValueField(wireName: r'mode')
  ScheduleOverrideResponseModeEnum? get mode;
  // enum modeEnum {  INTERVAL,  EXPLICIT_TIMES,  };

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

  @BuiltValueField(wireName: r'times')
  BuiltList<String>? get times;

  ScheduleOverrideResponse._();

  factory ScheduleOverrideResponse(
          [void updates(ScheduleOverrideResponseBuilder b)]) =
      _$ScheduleOverrideResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScheduleOverrideResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScheduleOverrideResponse> get serializer =>
      _$ScheduleOverrideResponseSerializer();
}

class _$ScheduleOverrideResponseSerializer
    implements PrimitiveSerializer<ScheduleOverrideResponse> {
  @override
  final Iterable<Type> types = const [
    ScheduleOverrideResponse,
    _$ScheduleOverrideResponse
  ];

  @override
  final String wireName = r'ScheduleOverrideResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScheduleOverrideResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
      );
    }
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType(ScheduleOverrideResponseKindEnum),
      );
    }
    if (object.mode != null) {
      yield r'mode';
      yield serializers.serialize(
        object.mode,
        specifiedType: const FullType(ScheduleOverrideResponseModeEnum),
      );
    }
    if (object.intervals != null) {
      yield r'intervals';
      yield serializers.serialize(
        object.intervals,
        specifiedType: const FullType(BuiltList, [FullType(WorkIntervalDto)]),
      );
    }
    if (object.times != null) {
      yield r'times';
      yield serializers.serialize(
        object.times,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ScheduleOverrideResponse object, {
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
    required ScheduleOverrideResponseBuilder result,
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
            specifiedType: const FullType(ScheduleOverrideResponseKindEnum),
          ) as ScheduleOverrideResponseKindEnum;
          result.kind = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ScheduleOverrideResponseModeEnum),
          ) as ScheduleOverrideResponseModeEnum;
          result.mode = valueDes;
          break;
        case r'intervals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(WorkIntervalDto)]),
          ) as BuiltList<WorkIntervalDto>;
          result.intervals.replace(valueDes);
          break;
        case r'times':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.times.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScheduleOverrideResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScheduleOverrideResponseBuilder();
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

class ScheduleOverrideResponseKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'DAY_OFF')
  static const ScheduleOverrideResponseKindEnum DAY_OFF =
      _$scheduleOverrideResponseKindEnum_DAY_OFF;
  @BuiltValueEnumConst(wireName: r'CUSTOM_HOURS')
  static const ScheduleOverrideResponseKindEnum CUSTOM_HOURS =
      _$scheduleOverrideResponseKindEnum_CUSTOM_HOURS;

  static Serializer<ScheduleOverrideResponseKindEnum> get serializer =>
      _$scheduleOverrideResponseKindEnumSerializer;

  const ScheduleOverrideResponseKindEnum._(String name) : super(name);

  static BuiltSet<ScheduleOverrideResponseKindEnum> get values =>
      _$scheduleOverrideResponseKindEnumValues;
  static ScheduleOverrideResponseKindEnum valueOf(String name) =>
      _$scheduleOverrideResponseKindEnumValueOf(name);
}

class ScheduleOverrideResponseModeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'INTERVAL')
  static const ScheduleOverrideResponseModeEnum INTERVAL =
      _$scheduleOverrideResponseModeEnum_INTERVAL;
  @BuiltValueEnumConst(wireName: r'EXPLICIT_TIMES')
  static const ScheduleOverrideResponseModeEnum EXPLICIT_TIMES =
      _$scheduleOverrideResponseModeEnum_EXPLICIT_TIMES;

  static Serializer<ScheduleOverrideResponseModeEnum> get serializer =>
      _$scheduleOverrideResponseModeEnumSerializer;

  const ScheduleOverrideResponseModeEnum._(String name) : super(name);

  static BuiltSet<ScheduleOverrideResponseModeEnum> get values =>
      _$scheduleOverrideResponseModeEnumValues;
  static ScheduleOverrideResponseModeEnum valueOf(String name) =>
      _$scheduleOverrideResponseModeEnumValueOf(name);
}
