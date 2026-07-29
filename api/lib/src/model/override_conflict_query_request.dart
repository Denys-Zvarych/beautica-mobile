//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/work_interval_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'override_conflict_query_request.g.dart';

/// OverrideConflictQueryRequest
///
/// Properties:
/// * [from]
/// * [to]
/// * [kind]
/// * [mode]
/// * [intervals]
/// * [times]
/// * [kindConsistent]
@BuiltValue()
abstract class OverrideConflictQueryRequest
    implements
        Built<OverrideConflictQueryRequest,
            OverrideConflictQueryRequestBuilder> {
  @BuiltValueField(wireName: r'from')
  Date get from;

  @BuiltValueField(wireName: r'to')
  Date get to;

  @BuiltValueField(wireName: r'kind')
  OverrideConflictQueryRequestKindEnum get kind;
  // enum kindEnum {  DAY_OFF,  CUSTOM_HOURS,  };

  @BuiltValueField(wireName: r'mode')
  OverrideConflictQueryRequestModeEnum? get mode;
  // enum modeEnum {  INTERVAL,  EXPLICIT_TIMES,  };

  @BuiltValueField(wireName: r'intervals')
  BuiltList<WorkIntervalDto>? get intervals;

  @BuiltValueField(wireName: r'times')
  BuiltList<String>? get times;

  @BuiltValueField(wireName: r'kindConsistent')
  bool? get kindConsistent;

  OverrideConflictQueryRequest._();

  factory OverrideConflictQueryRequest(
          [void updates(OverrideConflictQueryRequestBuilder b)]) =
      _$OverrideConflictQueryRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OverrideConflictQueryRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OverrideConflictQueryRequest> get serializer =>
      _$OverrideConflictQueryRequestSerializer();
}

class _$OverrideConflictQueryRequestSerializer
    implements PrimitiveSerializer<OverrideConflictQueryRequest> {
  @override
  final Iterable<Type> types = const [
    OverrideConflictQueryRequest,
    _$OverrideConflictQueryRequest
  ];

  @override
  final String wireName = r'OverrideConflictQueryRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OverrideConflictQueryRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'from';
    yield serializers.serialize(
      object.from,
      specifiedType: const FullType(Date),
    );
    yield r'to';
    yield serializers.serialize(
      object.to,
      specifiedType: const FullType(Date),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(OverrideConflictQueryRequestKindEnum),
    );
    if (object.mode != null) {
      yield r'mode';
      yield serializers.serialize(
        object.mode,
        specifiedType: const FullType(OverrideConflictQueryRequestModeEnum),
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
    OverrideConflictQueryRequest object, {
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
    required OverrideConflictQueryRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.from = valueDes;
          break;
        case r'to':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.to = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OverrideConflictQueryRequestKindEnum),
          ) as OverrideConflictQueryRequestKindEnum;
          result.kind = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OverrideConflictQueryRequestModeEnum),
          ) as OverrideConflictQueryRequestModeEnum;
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
  OverrideConflictQueryRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OverrideConflictQueryRequestBuilder();
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

class OverrideConflictQueryRequestKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'DAY_OFF')
  static const OverrideConflictQueryRequestKindEnum DAY_OFF =
      _$overrideConflictQueryRequestKindEnum_DAY_OFF;
  @BuiltValueEnumConst(wireName: r'CUSTOM_HOURS')
  static const OverrideConflictQueryRequestKindEnum CUSTOM_HOURS =
      _$overrideConflictQueryRequestKindEnum_CUSTOM_HOURS;

  static Serializer<OverrideConflictQueryRequestKindEnum> get serializer =>
      _$overrideConflictQueryRequestKindEnumSerializer;

  const OverrideConflictQueryRequestKindEnum._(String name) : super(name);

  static BuiltSet<OverrideConflictQueryRequestKindEnum> get values =>
      _$overrideConflictQueryRequestKindEnumValues;
  static OverrideConflictQueryRequestKindEnum valueOf(String name) =>
      _$overrideConflictQueryRequestKindEnumValueOf(name);
}

class OverrideConflictQueryRequestModeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'INTERVAL')
  static const OverrideConflictQueryRequestModeEnum INTERVAL =
      _$overrideConflictQueryRequestModeEnum_INTERVAL;
  @BuiltValueEnumConst(wireName: r'EXPLICIT_TIMES')
  static const OverrideConflictQueryRequestModeEnum EXPLICIT_TIMES =
      _$overrideConflictQueryRequestModeEnum_EXPLICIT_TIMES;

  static Serializer<OverrideConflictQueryRequestModeEnum> get serializer =>
      _$overrideConflictQueryRequestModeEnumSerializer;

  const OverrideConflictQueryRequestModeEnum._(String name) : super(name);

  static BuiltSet<OverrideConflictQueryRequestModeEnum> get values =>
      _$overrideConflictQueryRequestModeEnumValues;
  static OverrideConflictQueryRequestModeEnum valueOf(String name) =>
      _$overrideConflictQueryRequestModeEnumValueOf(name);
}
