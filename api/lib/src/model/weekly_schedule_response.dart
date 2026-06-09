//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/weekly_schedule_day_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'weekly_schedule_response.g.dart';

/// WeeklyScheduleResponse
///
/// Properties:
/// * [id]
/// * [validFrom]
/// * [validTo]
/// * [days]
@BuiltValue()
abstract class WeeklyScheduleResponse
    implements Built<WeeklyScheduleResponse, WeeklyScheduleResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'validFrom')
  Date? get validFrom;

  @BuiltValueField(wireName: r'validTo')
  Date? get validTo;

  @BuiltValueField(wireName: r'days')
  BuiltList<WeeklyScheduleDayResponse>? get days;

  WeeklyScheduleResponse._();

  factory WeeklyScheduleResponse(
          [void updates(WeeklyScheduleResponseBuilder b)]) =
      _$WeeklyScheduleResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WeeklyScheduleResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WeeklyScheduleResponse> get serializer =>
      _$WeeklyScheduleResponseSerializer();
}

class _$WeeklyScheduleResponseSerializer
    implements PrimitiveSerializer<WeeklyScheduleResponse> {
  @override
  final Iterable<Type> types = const [
    WeeklyScheduleResponse,
    _$WeeklyScheduleResponse
  ];

  @override
  final String wireName = r'WeeklyScheduleResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WeeklyScheduleResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.validFrom != null) {
      yield r'validFrom';
      yield serializers.serialize(
        object.validFrom,
        specifiedType: const FullType(Date),
      );
    }
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
            const FullType(BuiltList, [FullType(WeeklyScheduleDayResponse)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WeeklyScheduleResponse object, {
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
    required WeeklyScheduleResponseBuilder result,
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
            specifiedType: const FullType(
                BuiltList, [FullType(WeeklyScheduleDayResponse)]),
          ) as BuiltList<WeeklyScheduleDayResponse>;
          result.days.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WeeklyScheduleResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WeeklyScheduleResponseBuilder();
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
