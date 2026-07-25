//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appointment_reschedule_request.g.dart';

/// AppointmentRescheduleRequest
///
/// Properties:
/// * [newStartsAt]
@BuiltValue()
abstract class AppointmentRescheduleRequest
    implements
        Built<AppointmentRescheduleRequest,
            AppointmentRescheduleRequestBuilder> {
  @BuiltValueField(wireName: r'newStartsAt')
  DateTime get newStartsAt;

  AppointmentRescheduleRequest._();

  factory AppointmentRescheduleRequest(
          [void updates(AppointmentRescheduleRequestBuilder b)]) =
      _$AppointmentRescheduleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppointmentRescheduleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppointmentRescheduleRequest> get serializer =>
      _$AppointmentRescheduleRequestSerializer();
}

class _$AppointmentRescheduleRequestSerializer
    implements PrimitiveSerializer<AppointmentRescheduleRequest> {
  @override
  final Iterable<Type> types = const [
    AppointmentRescheduleRequest,
    _$AppointmentRescheduleRequest
  ];

  @override
  final String wireName = r'AppointmentRescheduleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppointmentRescheduleRequest object, {
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
    AppointmentRescheduleRequest object, {
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
    required AppointmentRescheduleRequestBuilder result,
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
  AppointmentRescheduleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppointmentRescheduleRequestBuilder();
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
