//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'client_authored_review_response.g.dart';

/// The review this booking's CLIENT left about the master (rating + full comment). Null when no review exists for the booking. NOT the provider's review of the client — that is a separate entity, written through POST /client-reviews and gated by providerCanReviewClient.
///
/// Properties:
/// * [rating] - The client's star rating for this booking, 1-5.
/// * [comment] - The client's review text, verbatim and unabridged, or null when they rated without writing anything. Already public via GET /masters/{id}/reviews — never truncated or masked here.
@BuiltValue()
abstract class ClientAuthoredReviewResponse
    implements
        Built<ClientAuthoredReviewResponse,
            ClientAuthoredReviewResponseBuilder> {
  /// The client's star rating for this booking, 1-5.
  @BuiltValueField(wireName: r'rating')
  int? get rating;

  /// The client's review text, verbatim and unabridged, or null when they rated without writing anything. Already public via GET /masters/{id}/reviews — never truncated or masked here.
  @BuiltValueField(wireName: r'comment')
  String? get comment;

  ClientAuthoredReviewResponse._();

  factory ClientAuthoredReviewResponse(
          [void updates(ClientAuthoredReviewResponseBuilder b)]) =
      _$ClientAuthoredReviewResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClientAuthoredReviewResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClientAuthoredReviewResponse> get serializer =>
      _$ClientAuthoredReviewResponseSerializer();
}

class _$ClientAuthoredReviewResponseSerializer
    implements PrimitiveSerializer<ClientAuthoredReviewResponse> {
  @override
  final Iterable<Type> types = const [
    ClientAuthoredReviewResponse,
    _$ClientAuthoredReviewResponse
  ];

  @override
  final String wireName = r'ClientAuthoredReviewResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClientAuthoredReviewResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.rating != null) {
      yield r'rating';
      yield serializers.serialize(
        object.rating,
        specifiedType: const FullType(int),
      );
    }
    if (object.comment != null) {
      yield r'comment';
      yield serializers.serialize(
        object.comment,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClientAuthoredReviewResponse object, {
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
    required ClientAuthoredReviewResponseBuilder result,
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
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
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
  ClientAuthoredReviewResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClientAuthoredReviewResponseBuilder();
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
