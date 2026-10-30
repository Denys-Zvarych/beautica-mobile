//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_review_item_request.g.dart';

/// GuestReviewItemRequest
///
/// Properties:
/// * [bookingId]
/// * [rating]
/// * [comment]
@BuiltValue()
abstract class GuestReviewItemRequest
    implements Built<GuestReviewItemRequest, GuestReviewItemRequestBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String get bookingId;

  @BuiltValueField(wireName: r'rating')
  int get rating;

  @BuiltValueField(wireName: r'comment')
  String? get comment;

  GuestReviewItemRequest._();

  factory GuestReviewItemRequest(
          [void updates(GuestReviewItemRequestBuilder b)]) =
      _$GuestReviewItemRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestReviewItemRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestReviewItemRequest> get serializer =>
      _$GuestReviewItemRequestSerializer();
}

class _$GuestReviewItemRequestSerializer
    implements PrimitiveSerializer<GuestReviewItemRequest> {
  @override
  final Iterable<Type> types = const [
    GuestReviewItemRequest,
    _$GuestReviewItemRequest
  ];

  @override
  final String wireName = r'GuestReviewItemRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestReviewItemRequest object, {
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
    GuestReviewItemRequest object, {
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
    required GuestReviewItemRequestBuilder result,
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
  GuestReviewItemRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestReviewItemRequestBuilder();
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
