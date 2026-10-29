//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/guest_review_item_request.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_review_submit_request.g.dart';

/// GuestReviewSubmitRequest
///
/// Properties:
/// * [turnstileToken]
/// * [items]
@BuiltValue()
abstract class GuestReviewSubmitRequest
    implements
        Built<GuestReviewSubmitRequest, GuestReviewSubmitRequestBuilder> {
  @BuiltValueField(wireName: r'turnstileToken')
  String? get turnstileToken;

  @BuiltValueField(wireName: r'items')
  BuiltList<GuestReviewItemRequest> get items;

  GuestReviewSubmitRequest._();

  factory GuestReviewSubmitRequest(
          [void updates(GuestReviewSubmitRequestBuilder b)]) =
      _$GuestReviewSubmitRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestReviewSubmitRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestReviewSubmitRequest> get serializer =>
      _$GuestReviewSubmitRequestSerializer();
}

class _$GuestReviewSubmitRequestSerializer
    implements PrimitiveSerializer<GuestReviewSubmitRequest> {
  @override
  final Iterable<Type> types = const [
    GuestReviewSubmitRequest,
    _$GuestReviewSubmitRequest
  ];

  @override
  final String wireName = r'GuestReviewSubmitRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestReviewSubmitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.turnstileToken != null) {
      yield r'turnstileToken';
      yield serializers.serialize(
        object.turnstileToken,
        specifiedType: const FullType(String),
      );
    }
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType:
          const FullType(BuiltList, [FullType(GuestReviewItemRequest)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestReviewSubmitRequest object, {
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
    required GuestReviewSubmitRequestBuilder result,
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
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(GuestReviewItemRequest)]),
          ) as BuiltList<GuestReviewItemRequest>;
          result.items.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestReviewSubmitRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestReviewSubmitRequestBuilder();
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
