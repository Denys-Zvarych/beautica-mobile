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
/// * [intervals]
@BuiltValue()
abstract class ScheduleOverrideResponse
    implements
        Built<ScheduleOverrideResponse, ScheduleOverrideResponseBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'kind')
  ScheduleOverrideResponseKindEnum? get kind;
  // enum kindEnum {  DAY_OFF,  CUSTOM_HOURS,  };

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

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
    if (object.intervals != null) {
      yield r'intervals';
      yield serializers.serialize(
        object.intervals,
        specifiedType: const FullType(BuiltList, [FullType(WorkIntervalDto)]),
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
        case r'intervals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(WorkIntervalDto)]),
          ) as BuiltList<WorkIntervalDto>;
          result.intervals.replace(valueDes);
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
