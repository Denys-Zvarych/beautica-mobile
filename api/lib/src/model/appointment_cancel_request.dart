//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appointment_cancel_request.g.dart';

/// AppointmentCancelRequest
///
/// Properties:
/// * [clientCancellationNote]
@BuiltValue()
abstract class AppointmentCancelRequest
    implements
        Built<AppointmentCancelRequest, AppointmentCancelRequestBuilder> {
  @BuiltValueField(wireName: r'clientCancellationNote')
  String? get clientCancellationNote;

  AppointmentCancelRequest._();

  factory AppointmentCancelRequest(
          [void updates(AppointmentCancelRequestBuilder b)]) =
      _$AppointmentCancelRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppointmentCancelRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppointmentCancelRequest> get serializer =>
      _$AppointmentCancelRequestSerializer();
}

class _$AppointmentCancelRequestSerializer
    implements PrimitiveSerializer<AppointmentCancelRequest> {
  @override
  final Iterable<Type> types = const [
    AppointmentCancelRequest,
    _$AppointmentCancelRequest
  ];

  @override
  final String wireName = r'AppointmentCancelRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppointmentCancelRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.clientCancellationNote != null) {
      yield r'clientCancellationNote';
      yield serializers.serialize(
        object.clientCancellationNote,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AppointmentCancelRequest object, {
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
    required AppointmentCancelRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'clientCancellationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientCancellationNote = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppointmentCancelRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppointmentCancelRequestBuilder();
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
