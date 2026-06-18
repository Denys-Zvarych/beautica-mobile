//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'reschedule_booking_request.g.dart';

/// RescheduleBookingRequest
///
/// Properties:
/// * [newStartsAt]
@BuiltValue()
abstract class RescheduleBookingRequest
    implements
        Built<RescheduleBookingRequest, RescheduleBookingRequestBuilder> {
  @BuiltValueField(wireName: r'newStartsAt')
  DateTime get newStartsAt;

  RescheduleBookingRequest._();

  factory RescheduleBookingRequest(
          [void updates(RescheduleBookingRequestBuilder b)]) =
      _$RescheduleBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RescheduleBookingRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RescheduleBookingRequest> get serializer =>
      _$RescheduleBookingRequestSerializer();
}

class _$RescheduleBookingRequestSerializer
    implements PrimitiveSerializer<RescheduleBookingRequest> {
  @override
  final Iterable<Type> types = const [
    RescheduleBookingRequest,
    _$RescheduleBookingRequest
  ];

  @override
  final String wireName = r'RescheduleBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RescheduleBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'newStartsAt';
    yield serializers.serialize(
      object.newStartsAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RescheduleBookingRequest object, {
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
    required RescheduleBookingRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'newStartsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.newStartsAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RescheduleBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RescheduleBookingRequestBuilder();
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
