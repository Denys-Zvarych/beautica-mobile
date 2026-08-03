//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appointment_item_reschedule_request.g.dart';

/// AppointmentItemRescheduleRequest
///
/// Properties:
/// * [newStartsAt] - The new start of THIS service line only. Siblings keep their windows; the visit's items may end up non-contiguous (gaps are legal, overlaps are not — phase 30.1 L3).
@BuiltValue()
abstract class AppointmentItemRescheduleRequest
    implements
        Built<AppointmentItemRescheduleRequest,
            AppointmentItemRescheduleRequestBuilder> {
  /// The new start of THIS service line only. Siblings keep their windows; the visit's items may end up non-contiguous (gaps are legal, overlaps are not — phase 30.1 L3).
  @BuiltValueField(wireName: r'newStartsAt')
  DateTime get newStartsAt;

  AppointmentItemRescheduleRequest._();

  factory AppointmentItemRescheduleRequest(
          [void updates(AppointmentItemRescheduleRequestBuilder b)]) =
      _$AppointmentItemRescheduleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppointmentItemRescheduleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppointmentItemRescheduleRequest> get serializer =>
      _$AppointmentItemRescheduleRequestSerializer();
}

class _$AppointmentItemRescheduleRequestSerializer
    implements PrimitiveSerializer<AppointmentItemRescheduleRequest> {
  @override
  final Iterable<Type> types = const [
    AppointmentItemRescheduleRequest,
    _$AppointmentItemRescheduleRequest
  ];

  @override
  final String wireName = r'AppointmentItemRescheduleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppointmentItemRescheduleRequest object, {
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
    AppointmentItemRescheduleRequest object, {
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
    required AppointmentItemRescheduleRequestBuilder result,
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
  AppointmentItemRescheduleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppointmentItemRescheduleRequestBuilder();
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
