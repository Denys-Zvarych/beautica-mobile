//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/work_interval_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'weekly_schedule_day_request.g.dart';

/// WeeklyScheduleDayRequest
///
/// Properties:
/// * [dayOfWeek]
/// * [mode]
/// * [intervals]
/// * [times]
/// * [modeConsistent]
@BuiltValue()
abstract class WeeklyScheduleDayRequest
    implements
        Built<WeeklyScheduleDayRequest, WeeklyScheduleDayRequestBuilder> {
  @BuiltValueField(wireName: r'dayOfWeek')
  int? get dayOfWeek;

  @BuiltValueField(wireName: r'mode')
  WeeklyScheduleDayRequestModeEnum? get mode;
  // enum modeEnum {  INTERVAL,  EXPLICIT_TIMES,  };

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

  @BuiltValueField(wireName: r'times')
  BuiltList<String>? get times;

  @BuiltValueField(wireName: r'modeConsistent')
  bool? get modeConsistent;

  WeeklyScheduleDayRequest._();

  factory WeeklyScheduleDayRequest(
          [void updates(WeeklyScheduleDayRequestBuilder b)]) =
      _$WeeklyScheduleDayRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WeeklyScheduleDayRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WeeklyScheduleDayRequest> get serializer =>
      _$WeeklyScheduleDayRequestSerializer();
}

class _$WeeklyScheduleDayRequestSerializer
    implements PrimitiveSerializer<WeeklyScheduleDayRequest> {
  @override
  final Iterable<Type> types = const [
    WeeklyScheduleDayRequest,
    _$WeeklyScheduleDayRequest
  ];

  @override
  final String wireName = r'WeeklyScheduleDayRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WeeklyScheduleDayRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.dayOfWeek != null) {
      yield r'dayOfWeek';
      yield serializers.serialize(
        object.dayOfWeek,
        specifiedType: const FullType(int),
      );
    }
    if (object.mode != null) {
      yield r'mode';
      yield serializers.serialize(
        object.mode,
        specifiedType: const FullType(WeeklyScheduleDayRequestModeEnum),
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
    if (object.modeConsistent != null) {
      yield r'modeConsistent';
      yield serializers.serialize(
        object.modeConsistent,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WeeklyScheduleDayRequest object, {
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
    required WeeklyScheduleDayRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'dayOfWeek':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.dayOfWeek = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(WeeklyScheduleDayRequestModeEnum),
          ) as WeeklyScheduleDayRequestModeEnum;
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
        case r'modeConsistent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.modeConsistent = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WeeklyScheduleDayRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WeeklyScheduleDayRequestBuilder();
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

class WeeklyScheduleDayRequestModeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'INTERVAL')
  static const WeeklyScheduleDayRequestModeEnum INTERVAL =
      _$weeklyScheduleDayRequestModeEnum_INTERVAL;
  @BuiltValueEnumConst(wireName: r'EXPLICIT_TIMES')
  static const WeeklyScheduleDayRequestModeEnum EXPLICIT_TIMES =
      _$weeklyScheduleDayRequestModeEnum_EXPLICIT_TIMES;

  static Serializer<WeeklyScheduleDayRequestModeEnum> get serializer =>
      _$weeklyScheduleDayRequestModeEnumSerializer;

  const WeeklyScheduleDayRequestModeEnum._(String name) : super(name);

  static BuiltSet<WeeklyScheduleDayRequestModeEnum> get values =>
      _$weeklyScheduleDayRequestModeEnumValues;
  static WeeklyScheduleDayRequestModeEnum valueOf(String name) =>
      _$weeklyScheduleDayRequestModeEnumValueOf(name);
}
