//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/weekly_schedule_day_request.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'weekly_schedule_request.g.dart';

/// WeeklyScheduleRequest
///
/// Properties:
/// * [validFrom]
/// * [validTo]
/// * [days]
/// * [windowOrdered]
/// * [daysUnique]
@BuiltValue()
abstract class WeeklyScheduleRequest
    implements Built<WeeklyScheduleRequest, WeeklyScheduleRequestBuilder> {
  @BuiltValueField(wireName: r'validFrom')
  Date get validFrom;

  @BuiltValueField(wireName: r'validTo')
  Date? get validTo;

  @BuiltValueField(wireName: r'days')
  BuiltList<WeeklyScheduleDayRequest>? get days;

  @BuiltValueField(wireName: r'windowOrdered')
  bool? get windowOrdered;

  @BuiltValueField(wireName: r'daysUnique')
  bool? get daysUnique;

  WeeklyScheduleRequest._();

  factory WeeklyScheduleRequest(
      [void updates(WeeklyScheduleRequestBuilder b)]) = _$WeeklyScheduleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WeeklyScheduleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WeeklyScheduleRequest> get serializer =>
      _$WeeklyScheduleRequestSerializer();
}

class _$WeeklyScheduleRequestSerializer
    implements PrimitiveSerializer<WeeklyScheduleRequest> {
  @override
  final Iterable<Type> types = const [
    WeeklyScheduleRequest,
    _$WeeklyScheduleRequest
  ];

  @override
  final String wireName = r'WeeklyScheduleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WeeklyScheduleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'validFrom';
    yield serializers.serialize(
      object.validFrom,
      specifiedType: const FullType(Date),
    );
    if (object.validTo != null) {
      yield r'validTo';
      yield serializers.serialize(
        object.validTo,
        specifiedType: const FullType(Date),
      );
    }
    if (object.days != null) {
      yield r'days';
      yield serializers.serialize(
        object.days,
        specifiedType:
            const FullType(BuiltList, [FullType(WeeklyScheduleDayRequest)]),
      );
    }
    if (object.windowOrdered != null) {
      yield r'windowOrdered';
      yield serializers.serialize(
        object.windowOrdered,
        specifiedType: const FullType(bool),
      );
    }
    if (object.daysUnique != null) {
      yield r'daysUnique';
      yield serializers.serialize(
        object.daysUnique,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WeeklyScheduleRequest object, {
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
    required WeeklyScheduleRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'validFrom':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.validFrom = valueDes;
          break;
        case r'validTo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.validTo = valueDes;
          break;
        case r'days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(WeeklyScheduleDayRequest)]),
          ) as BuiltList<WeeklyScheduleDayRequest>;
          result.days.replace(valueDes);
          break;
        case r'windowOrdered':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.windowOrdered = valueDes;
          break;
        case r'daysUnique':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.daysUnique = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WeeklyScheduleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WeeklyScheduleRequestBuilder();
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
