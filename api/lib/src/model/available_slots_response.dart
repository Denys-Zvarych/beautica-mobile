//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/available_slot_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'available_slots_response.g.dart';

/// AvailableSlotsResponse
///
/// Properties:
/// * [date]
/// * [slots]
@BuiltValue()
abstract class AvailableSlotsResponse
    implements Built<AvailableSlotsResponse, AvailableSlotsResponseBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'slots')
  BuiltList<AvailableSlotResponse>? get slots;

  AvailableSlotsResponse._();

  factory AvailableSlotsResponse(
          [void updates(AvailableSlotsResponseBuilder b)]) =
      _$AvailableSlotsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AvailableSlotsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AvailableSlotsResponse> get serializer =>
      _$AvailableSlotsResponseSerializer();
}

class _$AvailableSlotsResponseSerializer
    implements PrimitiveSerializer<AvailableSlotsResponse> {
  @override
  final Iterable<Type> types = const [
    AvailableSlotsResponse,
    _$AvailableSlotsResponse
  ];

  @override
  final String wireName = r'AvailableSlotsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AvailableSlotsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
      );
    }
    if (object.slots != null) {
      yield r'slots';
      yield serializers.serialize(
        object.slots,
        specifiedType:
            const FullType(BuiltList, [FullType(AvailableSlotResponse)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AvailableSlotsResponse object, {
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
    required AvailableSlotsResponseBuilder result,
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
        case r'slots':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(AvailableSlotResponse)]),
          ) as BuiltList<AvailableSlotResponse>;
          result.slots.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AvailableSlotsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AvailableSlotsResponseBuilder();
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
