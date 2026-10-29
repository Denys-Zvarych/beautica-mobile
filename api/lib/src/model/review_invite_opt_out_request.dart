//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_invite_opt_out_request.g.dart';

/// ReviewInviteOptOutRequest
///
/// Properties:
/// * [turnstileToken]
@BuiltValue()
abstract class ReviewInviteOptOutRequest
    implements
        Built<ReviewInviteOptOutRequest, ReviewInviteOptOutRequestBuilder> {
  @BuiltValueField(wireName: r'turnstileToken')
  String? get turnstileToken;

  ReviewInviteOptOutRequest._();

  factory ReviewInviteOptOutRequest(
          [void updates(ReviewInviteOptOutRequestBuilder b)]) =
      _$ReviewInviteOptOutRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewInviteOptOutRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewInviteOptOutRequest> get serializer =>
      _$ReviewInviteOptOutRequestSerializer();
}

class _$ReviewInviteOptOutRequestSerializer
    implements PrimitiveSerializer<ReviewInviteOptOutRequest> {
  @override
  final Iterable<Type> types = const [
    ReviewInviteOptOutRequest,
    _$ReviewInviteOptOutRequest
  ];

  @override
  final String wireName = r'ReviewInviteOptOutRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewInviteOptOutRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.turnstileToken != null) {
      yield r'turnstileToken';
      yield serializers.serialize(
        object.turnstileToken,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewInviteOptOutRequest object, {
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
    required ReviewInviteOptOutRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'turnstileToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.turnstileToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewInviteOptOutRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewInviteOptOutRequestBuilder();
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
