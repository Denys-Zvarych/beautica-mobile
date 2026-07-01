//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_booking_request.g.dart';

/// GuestBookingRequest
///
/// Properties:
/// * [serviceId]
/// * [startsAt]
/// * [name]
/// * [surname]
@BuiltValue()
abstract class GuestBookingRequest
    implements Built<GuestBookingRequest, GuestBookingRequestBuilder> {
  @BuiltValueField(wireName: r'serviceId')
  String get serviceId;

  @BuiltValueField(wireName: r'startsAt')
  DateTime get startsAt;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'surname')
  String get surname;

  GuestBookingRequest._();

  factory GuestBookingRequest([void updates(GuestBookingRequestBuilder b)]) =
      _$GuestBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestBookingRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestBookingRequest> get serializer =>
      _$GuestBookingRequestSerializer();
}

class _$GuestBookingRequestSerializer
    implements PrimitiveSerializer<GuestBookingRequest> {
  @override
  final Iterable<Type> types = const [
    GuestBookingRequest,
    _$GuestBookingRequest
  ];

  @override
  final String wireName = r'GuestBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'serviceId';
    yield serializers.serialize(
      object.serviceId,
      specifiedType: const FullType(String),
    );
    yield r'startsAt';
    yield serializers.serialize(
      object.startsAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'surname';
    yield serializers.serialize(
      object.surname,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestBookingRequest object, {
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
    required GuestBookingRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'serviceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceId = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'surname':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.surname = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestBookingRequestBuilder();
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
