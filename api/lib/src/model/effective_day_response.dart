//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/work_interval_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'effective_day_response.g.dart';

/// EffectiveDayResponse
///
/// Properties:
/// * [date]
/// * [source_]
/// * [intervals]
/// * [reason]
@BuiltValue()
abstract class EffectiveDayResponse
    implements Built<EffectiveDayResponse, EffectiveDayResponseBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'source')
  EffectiveDayResponseSource_Enum? get source_;
  // enum source_Enum {  TEMPLATE,  OVERRIDE_CUSTOM,  OVERRIDE_DAY_OFF,  NO_SCHEDULE,  };

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

  @BuiltValueField(wireName: r'reason')
  EffectiveDayResponseReasonEnum? get reason;
  // enum reasonEnum {  VACATION,  HOLIDAY,  SICK_DAY,  OTHER,  };

  EffectiveDayResponse._();

  factory EffectiveDayResponse([void updates(EffectiveDayResponseBuilder b)]) =
      _$EffectiveDayResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EffectiveDayResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EffectiveDayResponse> get serializer =>
      _$EffectiveDayResponseSerializer();
}

class _$EffectiveDayResponseSerializer
    implements PrimitiveSerializer<EffectiveDayResponse> {
  @override
  final Iterable<Type> types = const [
    EffectiveDayResponse,
    _$EffectiveDayResponse
  ];

  @override
  final String wireName = r'EffectiveDayResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EffectiveDayResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
      );
    }
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType(EffectiveDayResponseSource_Enum),
      );
    }
    if (object.intervals != null) {
      yield r'intervals';
      yield serializers.serialize(
        object.intervals,
        specifiedType: const FullType(BuiltList, [FullType(WorkIntervalDto)]),
      );
    }
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(EffectiveDayResponseReasonEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EffectiveDayResponse object, {
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
    required EffectiveDayResponseBuilder result,
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
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EffectiveDayResponseSource_Enum),
          ) as EffectiveDayResponseSource_Enum;
          result.source_ = valueDes;
          break;
        case r'intervals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(WorkIntervalDto)]),
          ) as BuiltList<WorkIntervalDto>;
          result.intervals.replace(valueDes);
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EffectiveDayResponseReasonEnum),
          ) as EffectiveDayResponseReasonEnum;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EffectiveDayResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EffectiveDayResponseBuilder();
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

class EffectiveDayResponseSource_Enum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'TEMPLATE')
  static const EffectiveDayResponseSource_Enum TEMPLATE =
      _$effectiveDayResponseSourceEnum_TEMPLATE;
  @BuiltValueEnumConst(wireName: r'OVERRIDE_CUSTOM')
  static const EffectiveDayResponseSource_Enum OVERRIDE_CUSTOM =
      _$effectiveDayResponseSourceEnum_OVERRIDE_CUSTOM;
  @BuiltValueEnumConst(wireName: r'OVERRIDE_DAY_OFF')
  static const EffectiveDayResponseSource_Enum OVERRIDE_DAY_OFF =
      _$effectiveDayResponseSourceEnum_OVERRIDE_DAY_OFF;
  @BuiltValueEnumConst(wireName: r'NO_SCHEDULE')
  static const EffectiveDayResponseSource_Enum NO_SCHEDULE =
      _$effectiveDayResponseSourceEnum_NO_SCHEDULE;

  static Serializer<EffectiveDayResponseSource_Enum> get serializer =>
      _$effectiveDayResponseSourceEnumSerializer;

  const EffectiveDayResponseSource_Enum._(String name) : super(name);

  static BuiltSet<EffectiveDayResponseSource_Enum> get values =>
      _$effectiveDayResponseSourceEnumValues;
  static EffectiveDayResponseSource_Enum valueOf(String name) =>
      _$effectiveDayResponseSourceEnumValueOf(name);
}

class EffectiveDayResponseReasonEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'VACATION')
  static const EffectiveDayResponseReasonEnum VACATION =
      _$effectiveDayResponseReasonEnum_VACATION;
  @BuiltValueEnumConst(wireName: r'HOLIDAY')
  static const EffectiveDayResponseReasonEnum HOLIDAY =
      _$effectiveDayResponseReasonEnum_HOLIDAY;
  @BuiltValueEnumConst(wireName: r'SICK_DAY')
  static const EffectiveDayResponseReasonEnum SICK_DAY =
      _$effectiveDayResponseReasonEnum_SICK_DAY;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const EffectiveDayResponseReasonEnum OTHER =
      _$effectiveDayResponseReasonEnum_OTHER;

  static Serializer<EffectiveDayResponseReasonEnum> get serializer =>
      _$effectiveDayResponseReasonEnumSerializer;

  const EffectiveDayResponseReasonEnum._(String name) : super(name);

  static BuiltSet<EffectiveDayResponseReasonEnum> get values =>
      _$effectiveDayResponseReasonEnumValues;
  static EffectiveDayResponseReasonEnum valueOf(String name) =>
      _$effectiveDayResponseReasonEnumValueOf(name);
}
