//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_exception_request.g.dart';

/// ScheduleExceptionRequest
///
/// Properties:
/// * [date]
/// * [reason]
/// * [note]
@BuiltValue()
abstract class ScheduleExceptionRequest
    implements
        Built<ScheduleExceptionRequest, ScheduleExceptionRequestBuilder> {
  @BuiltValueField(wireName: r'date')
  Date get date;

  @BuiltValueField(wireName: r'reason')
  ScheduleExceptionRequestReasonEnum get reason;
  // enum reasonEnum {  VACATION,  HOLIDAY,  SICK_DAY,  OTHER,  };

  @BuiltValueField(wireName: r'note')
  String? get note;

  ScheduleExceptionRequest._();

  factory ScheduleExceptionRequest(
          [void updates(ScheduleExceptionRequestBuilder b)]) =
      _$ScheduleExceptionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScheduleExceptionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScheduleExceptionRequest> get serializer =>
      _$ScheduleExceptionRequestSerializer();
}

class _$ScheduleExceptionRequestSerializer
    implements PrimitiveSerializer<ScheduleExceptionRequest> {
  @override
  final Iterable<Type> types = const [
    ScheduleExceptionRequest,
    _$ScheduleExceptionRequest
  ];

  @override
  final String wireName = r'ScheduleExceptionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScheduleExceptionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'date';
    yield serializers.serialize(
      object.date,
      specifiedType: const FullType(Date),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(ScheduleExceptionRequestReasonEnum),
    );
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ScheduleExceptionRequest object, {
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
    required ScheduleExceptionRequestBuilder result,
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
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ScheduleExceptionRequestReasonEnum),
          ) as ScheduleExceptionRequestReasonEnum;
          result.reason = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.note = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScheduleExceptionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScheduleExceptionRequestBuilder();
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

class ScheduleExceptionRequestReasonEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'VACATION')
  static const ScheduleExceptionRequestReasonEnum VACATION =
      _$scheduleExceptionRequestReasonEnum_VACATION;
  @BuiltValueEnumConst(wireName: r'HOLIDAY')
  static const ScheduleExceptionRequestReasonEnum HOLIDAY =
      _$scheduleExceptionRequestReasonEnum_HOLIDAY;
  @BuiltValueEnumConst(wireName: r'SICK_DAY')
  static const ScheduleExceptionRequestReasonEnum SICK_DAY =
      _$scheduleExceptionRequestReasonEnum_SICK_DAY;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const ScheduleExceptionRequestReasonEnum OTHER =
      _$scheduleExceptionRequestReasonEnum_OTHER;

  static Serializer<ScheduleExceptionRequestReasonEnum> get serializer =>
      _$scheduleExceptionRequestReasonEnumSerializer;

  const ScheduleExceptionRequestReasonEnum._(String name) : super(name);

  static BuiltSet<ScheduleExceptionRequestReasonEnum> get values =>
      _$scheduleExceptionRequestReasonEnumValues;
  static ScheduleExceptionRequestReasonEnum valueOf(String name) =>
      _$scheduleExceptionRequestReasonEnumValueOf(name);
}
