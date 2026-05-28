//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'available_slot_response.g.dart';

/// AvailableSlotResponse
///
/// Properties:
/// * [startsAt]
/// * [endsAt]
@BuiltValue()
abstract class AvailableSlotResponse
    implements Built<AvailableSlotResponse, AvailableSlotResponseBuilder> {
  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'endsAt')
  DateTime? get endsAt;

  AvailableSlotResponse._();

  factory AvailableSlotResponse(
      [void updates(AvailableSlotResponseBuilder b)]) = _$AvailableSlotResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AvailableSlotResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AvailableSlotResponse> get serializer =>
      _$AvailableSlotResponseSerializer();
}

class _$AvailableSlotResponseSerializer
    implements PrimitiveSerializer<AvailableSlotResponse> {
  @override
  final Iterable<Type> types = const [
    AvailableSlotResponse,
    _$AvailableSlotResponse
  ];

  @override
  final String wireName = r'AvailableSlotResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AvailableSlotResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.endsAt != null) {
      yield r'endsAt';
      yield serializers.serialize(
        object.endsAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AvailableSlotResponse object, {
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
    required AvailableSlotResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'endsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.endsAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AvailableSlotResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AvailableSlotResponseBuilder();
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
