//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_client_review_request.g.dart';

/// CreateClientReviewRequest
///
/// Properties:
/// * [bookingId]
/// * [rating]
/// * [comment]
@BuiltValue()
abstract class CreateClientReviewRequest
    implements
        Built<CreateClientReviewRequest, CreateClientReviewRequestBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String get bookingId;

  @BuiltValueField(wireName: r'rating')
  int get rating;

  @BuiltValueField(wireName: r'comment')
  String? get comment;

  CreateClientReviewRequest._();

  factory CreateClientReviewRequest(
          [void updates(CreateClientReviewRequestBuilder b)]) =
      _$CreateClientReviewRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateClientReviewRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateClientReviewRequest> get serializer =>
      _$CreateClientReviewRequestSerializer();
}

class _$CreateClientReviewRequestSerializer
    implements PrimitiveSerializer<CreateClientReviewRequest> {
  @override
  final Iterable<Type> types = const [
    CreateClientReviewRequest,
    _$CreateClientReviewRequest
  ];

  @override
  final String wireName = r'CreateClientReviewRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateClientReviewRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'bookingId';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
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
    CreateClientReviewRequest object, {
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
    required CreateClientReviewRequestBuilder result,
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
  CreateClientReviewRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateClientReviewRequestBuilder();
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
