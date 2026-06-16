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
/// * [mode]
/// * [intervals]
/// * [times]
/// * [kindConsistent]
@BuiltValue()
abstract class ScheduleOverrideRequest
    implements Built<ScheduleOverrideRequest, ScheduleOverrideRequestBuilder> {
  @BuiltValueField(wireName: r'date')
  Date get date;

  @BuiltValueField(wireName: r'kind')
  ScheduleOverrideRequestKindEnum get kind;
  // enum kindEnum {  DAY_OFF,  CUSTOM_HOURS,  };

  @BuiltValueField(wireName: r'mode')
  ScheduleOverrideRequestModeEnum? get mode;
  // enum modeEnum {  INTERVAL,  EXPLICIT_TIMES,  };

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

  @BuiltValueField(wireName: r'times')
  BuiltList<String>? get times;

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
    if (object.mode != null) {
      yield r'mode';
      yield serializers.serialize(
        object.mode,
        specifiedType: const FullType(ScheduleOverrideRequestModeEnum),
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
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ScheduleOverrideRequestModeEnum),
          ) as ScheduleOverrideRequestModeEnum;
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

class ScheduleOverrideRequestModeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'INTERVAL')
  static const ScheduleOverrideRequestModeEnum INTERVAL =
      _$scheduleOverrideRequestModeEnum_INTERVAL;
  @BuiltValueEnumConst(wireName: r'EXPLICIT_TIMES')
  static const ScheduleOverrideRequestModeEnum EXPLICIT_TIMES =
      _$scheduleOverrideRequestModeEnum_EXPLICIT_TIMES;

  static Serializer<ScheduleOverrideRequestModeEnum> get serializer =>
      _$scheduleOverrideRequestModeEnumSerializer;

  const ScheduleOverrideRequestModeEnum._(String name) : super(name);

  static BuiltSet<ScheduleOverrideRequestModeEnum> get values =>
      _$scheduleOverrideRequestModeEnumValues;
  static ScheduleOverrideRequestModeEnum valueOf(String name) =>
      _$scheduleOverrideRequestModeEnumValueOf(name);
}
