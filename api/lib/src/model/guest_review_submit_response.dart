//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_review_submit_response.g.dart';

/// GuestReviewSubmitResponse
///
/// Properties:
/// * [created]
@BuiltValue()
abstract class GuestReviewSubmitResponse
    implements
        Built<GuestReviewSubmitResponse, GuestReviewSubmitResponseBuilder> {
  @BuiltValueField(wireName: r'created')
  int? get created;

  GuestReviewSubmitResponse._();

  factory GuestReviewSubmitResponse(
          [void updates(GuestReviewSubmitResponseBuilder b)]) =
      _$GuestReviewSubmitResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestReviewSubmitResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestReviewSubmitResponse> get serializer =>
      _$GuestReviewSubmitResponseSerializer();
}

class _$GuestReviewSubmitResponseSerializer
    implements PrimitiveSerializer<GuestReviewSubmitResponse> {
  @override
  final Iterable<Type> types = const [
    GuestReviewSubmitResponse,
    _$GuestReviewSubmitResponse
  ];

  @override
  final String wireName = r'GuestReviewSubmitResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestReviewSubmitResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.created != null) {
      yield r'created';
      yield serializers.serialize(
        object.created,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestReviewSubmitResponse object, {
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
    required GuestReviewSubmitResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'created':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.created = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestReviewSubmitResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestReviewSubmitResponseBuilder();
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
