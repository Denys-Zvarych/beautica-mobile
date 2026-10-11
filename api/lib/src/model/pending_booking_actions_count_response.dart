//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pending_booking_actions_count_response.g.dart';

/// PendingBookingActionsCountResponse
///
/// Properties:
/// * [count] - Total bookings still needing a provider action: toClose + toRateClient. Uncapped; the client caps its display.
/// * [toClose] - CONFIRMED bookings whose end has passed (offer «Завершити» / «Не відбувся»).
/// * [toRateClient] - COMPLETED bookings with a registered client and no client review yet (offer «Залишити відгук про клієнта»).
@BuiltValue()
abstract class PendingBookingActionsCountResponse
    implements
        Built<PendingBookingActionsCountResponse,
            PendingBookingActionsCountResponseBuilder> {
  /// Total bookings still needing a provider action: toClose + toRateClient. Uncapped; the client caps its display.
  @BuiltValueField(wireName: r'count')
  int? get count;

  /// CONFIRMED bookings whose end has passed (offer «Завершити» / «Не відбувся»).
  @BuiltValueField(wireName: r'toClose')
  int? get toClose;

  /// COMPLETED bookings with a registered client and no client review yet (offer «Залишити відгук про клієнта»).
  @BuiltValueField(wireName: r'toRateClient')
  int? get toRateClient;

  PendingBookingActionsCountResponse._();

  factory PendingBookingActionsCountResponse(
          [void updates(PendingBookingActionsCountResponseBuilder b)]) =
      _$PendingBookingActionsCountResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PendingBookingActionsCountResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PendingBookingActionsCountResponse> get serializer =>
      _$PendingBookingActionsCountResponseSerializer();
}

class _$PendingBookingActionsCountResponseSerializer
    implements PrimitiveSerializer<PendingBookingActionsCountResponse> {
  @override
  final Iterable<Type> types = const [
    PendingBookingActionsCountResponse,
    _$PendingBookingActionsCountResponse
  ];

  @override
  final String wireName = r'PendingBookingActionsCountResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PendingBookingActionsCountResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.count != null) {
      yield r'count';
      yield serializers.serialize(
        object.count,
        specifiedType: const FullType(int),
      );
    }
    if (object.toClose != null) {
      yield r'toClose';
      yield serializers.serialize(
        object.toClose,
        specifiedType: const FullType(int),
      );
    }
    if (object.toRateClient != null) {
      yield r'toRateClient';
      yield serializers.serialize(
        object.toRateClient,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PendingBookingActionsCountResponse object, {
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
    required PendingBookingActionsCountResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        case r'toClose':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.toClose = valueDes;
          break;
        case r'toRateClient':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.toRateClient = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PendingBookingActionsCountResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PendingBookingActionsCountResponseBuilder();
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
