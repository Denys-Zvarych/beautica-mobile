//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/guest_client_dto.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_staff_booking_request.g.dart';

/// Creates a CONFIRMED, STAFF-sourced booking for a walk-in client on a master's calendar.
///
/// Properties:
/// * [masterServiceId] - MasterService (assignment) id the master performs.
/// * [startsAt] - ISO-8601 start instant; must land on the master's real slot grid.
/// * [guest]
@BuiltValue()
abstract class CreateStaffBookingRequest
    implements
        Built<CreateStaffBookingRequest, CreateStaffBookingRequestBuilder> {
  /// MasterService (assignment) id the master performs.
  @BuiltValueField(wireName: r'masterServiceId')
  String get masterServiceId;

  /// ISO-8601 start instant; must land on the master's real slot grid.
  @BuiltValueField(wireName: r'startsAt')
  DateTime get startsAt;

  @BuiltValueField(wireName: r'guest')
  GuestClientDto get guest;

  CreateStaffBookingRequest._();

  factory CreateStaffBookingRequest(
          [void updates(CreateStaffBookingRequestBuilder b)]) =
      _$CreateStaffBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateStaffBookingRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateStaffBookingRequest> get serializer =>
      _$CreateStaffBookingRequestSerializer();
}

class _$CreateStaffBookingRequestSerializer
    implements PrimitiveSerializer<CreateStaffBookingRequest> {
  @override
  final Iterable<Type> types = const [
    CreateStaffBookingRequest,
    _$CreateStaffBookingRequest
  ];

  @override
  final String wireName = r'CreateStaffBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateStaffBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'masterServiceId';
    yield serializers.serialize(
      object.masterServiceId,
      specifiedType: const FullType(String),
    );
    yield r'startsAt';
    yield serializers.serialize(
      object.startsAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'guest';
    yield serializers.serialize(
      object.guest,
      specifiedType: const FullType(GuestClientDto),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateStaffBookingRequest object, {
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
    required CreateStaffBookingRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterServiceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterServiceId = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'guest':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuestClientDto),
          ) as GuestClientDto;
          result.guest.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateStaffBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateStaffBookingRequestBuilder();
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
