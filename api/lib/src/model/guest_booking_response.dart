//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_booking_response.g.dart';

/// GuestBookingResponse
///
/// Properties:
/// * [bookingId]
/// * [appointmentId]
/// * [startsAt]
/// * [masterName]
/// * [serviceName]
/// * [durationMinutes]
/// * [cancelUrl]
@BuiltValue()
abstract class GuestBookingResponse
    implements Built<GuestBookingResponse, GuestBookingResponseBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'appointmentId')
  String? get appointmentId;

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'masterName')
  String? get masterName;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'durationMinutes')
  int? get durationMinutes;

  @BuiltValueField(wireName: r'cancelUrl')
  String? get cancelUrl;

  GuestBookingResponse._();

  factory GuestBookingResponse([void updates(GuestBookingResponseBuilder b)]) =
      _$GuestBookingResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestBookingResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestBookingResponse> get serializer =>
      _$GuestBookingResponseSerializer();
}

class _$GuestBookingResponseSerializer
    implements PrimitiveSerializer<GuestBookingResponse> {
  @override
  final Iterable<Type> types = const [
    GuestBookingResponse,
    _$GuestBookingResponse
  ];

  @override
  final String wireName = r'GuestBookingResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestBookingResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.bookingId != null) {
      yield r'bookingId';
      yield serializers.serialize(
        object.bookingId,
        specifiedType: const FullType(String),
      );
    }
    if (object.appointmentId != null) {
      yield r'appointmentId';
      yield serializers.serialize(
        object.appointmentId,
        specifiedType: const FullType(String),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.masterName != null) {
      yield r'masterName';
      yield serializers.serialize(
        object.masterName,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.durationMinutes != null) {
      yield r'durationMinutes';
      yield serializers.serialize(
        object.durationMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.cancelUrl != null) {
      yield r'cancelUrl';
      yield serializers.serialize(
        object.cancelUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestBookingResponse object, {
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
    required GuestBookingResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bookingId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'appointmentId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.appointmentId = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'masterName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterName = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'durationMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMinutes = valueDes;
          break;
        case r'cancelUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancelUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestBookingResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestBookingResponseBuilder();
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
