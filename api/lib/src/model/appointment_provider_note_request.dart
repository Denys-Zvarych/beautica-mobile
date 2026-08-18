//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appointment_provider_note_request.g.dart';

/// AppointmentProviderNoteRequest
///
/// Properties:
/// * [providerComment]
@BuiltValue()
abstract class AppointmentProviderNoteRequest
    implements
        Built<AppointmentProviderNoteRequest,
            AppointmentProviderNoteRequestBuilder> {
  @BuiltValueField(wireName: r'providerComment')
  String? get providerComment;

  AppointmentProviderNoteRequest._();

  factory AppointmentProviderNoteRequest(
          [void updates(AppointmentProviderNoteRequestBuilder b)]) =
      _$AppointmentProviderNoteRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppointmentProviderNoteRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppointmentProviderNoteRequest> get serializer =>
      _$AppointmentProviderNoteRequestSerializer();
}

class _$AppointmentProviderNoteRequestSerializer
    implements PrimitiveSerializer<AppointmentProviderNoteRequest> {
  @override
  final Iterable<Type> types = const [
    AppointmentProviderNoteRequest,
    _$AppointmentProviderNoteRequest
  ];

  @override
  final String wireName = r'AppointmentProviderNoteRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppointmentProviderNoteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.providerComment != null) {
      yield r'providerComment';
      yield serializers.serialize(
        object.providerComment,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AppointmentProviderNoteRequest object, {
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
    required AppointmentProviderNoteRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'providerComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.providerComment = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppointmentProviderNoteRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppointmentProviderNoteRequestBuilder();
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
