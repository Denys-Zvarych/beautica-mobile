//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'work_interval_dto.g.dart';

/// WorkIntervalDto
///
/// Properties:
/// * [startTime]
/// * [endTime]
/// * [ordered]
@BuiltValue()
abstract class WorkIntervalDto
    implements Built<WorkIntervalDto, WorkIntervalDtoBuilder> {
  @BuiltValueField(wireName: r'startTime')
  String get startTime;

  @BuiltValueField(wireName: r'endTime')
  String get endTime;

  @BuiltValueField(wireName: r'ordered')
  bool? get ordered;

  WorkIntervalDto._();

  factory WorkIntervalDto([void updates(WorkIntervalDtoBuilder b)]) =
      _$WorkIntervalDto;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WorkIntervalDtoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WorkIntervalDto> get serializer =>
      _$WorkIntervalDtoSerializer();
}

class _$WorkIntervalDtoSerializer
    implements PrimitiveSerializer<WorkIntervalDto> {
  @override
  final Iterable<Type> types = const [WorkIntervalDto, _$WorkIntervalDto];

  @override
  final String wireName = r'WorkIntervalDto';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WorkIntervalDto object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'startTime';
    yield serializers.serialize(
      object.startTime,
      specifiedType: const FullType(String),
    );
    yield r'endTime';
    yield serializers.serialize(
      object.endTime,
      specifiedType: const FullType(String),
    );
    if (object.ordered != null) {
      yield r'ordered';
      yield serializers.serialize(
        object.ordered,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WorkIntervalDto object, {
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
    required WorkIntervalDtoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'startTime':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.startTime = valueDes;
          break;
        case r'endTime':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endTime = valueDes;
          break;
        case r'ordered':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.ordered = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WorkIntervalDto deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WorkIntervalDtoBuilder();
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
