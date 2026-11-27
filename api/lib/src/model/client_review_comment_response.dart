//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'client_review_comment_response.g.dart';

/// ClientReviewCommentResponse
///
/// Properties:
/// * [reviewId]
/// * [visitMonth]
/// * [stars]
/// * [comment]
/// * [own]
@BuiltValue()
abstract class ClientReviewCommentResponse
    implements
        Built<ClientReviewCommentResponse, ClientReviewCommentResponseBuilder> {
  @BuiltValueField(wireName: r'reviewId')
  String? get reviewId;

  @BuiltValueField(wireName: r'visitMonth')
  String? get visitMonth;

  @BuiltValueField(wireName: r'stars')
  int? get stars;

  @BuiltValueField(wireName: r'comment')
  String? get comment;

  @BuiltValueField(wireName: r'own')
  bool? get own;

  ClientReviewCommentResponse._();

  factory ClientReviewCommentResponse(
          [void updates(ClientReviewCommentResponseBuilder b)]) =
      _$ClientReviewCommentResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClientReviewCommentResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClientReviewCommentResponse> get serializer =>
      _$ClientReviewCommentResponseSerializer();
}

class _$ClientReviewCommentResponseSerializer
    implements PrimitiveSerializer<ClientReviewCommentResponse> {
  @override
  final Iterable<Type> types = const [
    ClientReviewCommentResponse,
    _$ClientReviewCommentResponse
  ];

  @override
  final String wireName = r'ClientReviewCommentResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClientReviewCommentResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.reviewId != null) {
      yield r'reviewId';
      yield serializers.serialize(
        object.reviewId,
        specifiedType: const FullType(String),
      );
    }
    if (object.visitMonth != null) {
      yield r'visitMonth';
      yield serializers.serialize(
        object.visitMonth,
        specifiedType: const FullType(String),
      );
    }
    if (object.stars != null) {
      yield r'stars';
      yield serializers.serialize(
        object.stars,
        specifiedType: const FullType(int),
      );
    }
    if (object.comment != null) {
      yield r'comment';
      yield serializers.serialize(
        object.comment,
        specifiedType: const FullType(String),
      );
    }
    if (object.own != null) {
      yield r'own';
      yield serializers.serialize(
        object.own,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClientReviewCommentResponse object, {
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
    required ClientReviewCommentResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'reviewId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reviewId = valueDes;
          break;
        case r'visitMonth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.visitMonth = valueDes;
          break;
        case r'stars':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.stars = valueDes;
          break;
        case r'comment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.comment = valueDes;
          break;
        case r'own':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.own = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClientReviewCommentResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClientReviewCommentResponseBuilder();
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
