//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/work_interval_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'weekly_schedule_day_response.g.dart';

/// WeeklyScheduleDayResponse
///
/// Properties:
/// * [dayOfWeek]
/// * [intervals]
@BuiltValue()
abstract class WeeklyScheduleDayResponse
    implements
        Built<WeeklyScheduleDayResponse, WeeklyScheduleDayResponseBuilder> {
  @BuiltValueField(wireName: r'dayOfWeek')
  int? get dayOfWeek;

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

  WeeklyScheduleDayResponse._();

  factory WeeklyScheduleDayResponse(
          [void updates(WeeklyScheduleDayResponseBuilder b)]) =
      _$WeeklyScheduleDayResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WeeklyScheduleDayResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WeeklyScheduleDayResponse> get serializer =>
      _$WeeklyScheduleDayResponseSerializer();
}

class _$WeeklyScheduleDayResponseSerializer
    implements PrimitiveSerializer<WeeklyScheduleDayResponse> {
  @override
  final Iterable<Type> types = const [
    WeeklyScheduleDayResponse,
    _$WeeklyScheduleDayResponse
  ];

  @override
  final String wireName = r'WeeklyScheduleDayResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WeeklyScheduleDayResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.dayOfWeek != null) {
      yield r'dayOfWeek';
      yield serializers.serialize(
        object.dayOfWeek,
        specifiedType: const FullType(int),
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
    WeeklyScheduleDayResponse object, {
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
    required WeeklyScheduleDayResponseBuilder result,
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
  WeeklyScheduleDayResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WeeklyScheduleDayResponseBuilder();
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
