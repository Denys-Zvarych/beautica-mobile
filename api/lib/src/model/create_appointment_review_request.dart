//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_appointment_review_request.g.dart';

/// CreateAppointmentReviewRequest
///
/// Properties:
/// * [rating]
/// * [comment]
@BuiltValue()
abstract class CreateAppointmentReviewRequest
    implements
        Built<CreateAppointmentReviewRequest,
            CreateAppointmentReviewRequestBuilder> {
  @BuiltValueField(wireName: r'rating')
  int get rating;

  @BuiltValueField(wireName: r'comment')
  String? get comment;

  CreateAppointmentReviewRequest._();

  factory CreateAppointmentReviewRequest(
          [void updates(CreateAppointmentReviewRequestBuilder b)]) =
      _$CreateAppointmentReviewRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateAppointmentReviewRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateAppointmentReviewRequest> get serializer =>
      _$CreateAppointmentReviewRequestSerializer();
}

class _$CreateAppointmentReviewRequestSerializer
    implements PrimitiveSerializer<CreateAppointmentReviewRequest> {
  @override
  final Iterable<Type> types = const [
    CreateAppointmentReviewRequest,
    _$CreateAppointmentReviewRequest
  ];

  @override
  final String wireName = r'CreateAppointmentReviewRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateAppointmentReviewRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'rating';
    yield serializers.serialize(
      object.rating,
      specifiedType: const FullType(int),
    );
    if (object.comment != null) {
      yield r'comment';
      yield serializers.serialize(
        object.comment,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateAppointmentReviewRequest object, {
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
    required CreateAppointmentReviewRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rating = valueDes;
          break;
        case r'comment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.comment = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateAppointmentReviewRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateAppointmentReviewRequestBuilder();
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
