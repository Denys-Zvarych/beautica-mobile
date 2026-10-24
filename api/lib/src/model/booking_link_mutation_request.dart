//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_link_mutation_request.g.dart';

/// Optimistic concurrency token for a booking-link regenerate / revoke
///
/// Properties:
/// * [currentSlug] - The slug the app currently shows; null when the link is REVOKED. Mismatch with the stored slug → 409
@BuiltValue()
abstract class BookingLinkMutationRequest
    implements
        Built<BookingLinkMutationRequest, BookingLinkMutationRequestBuilder> {
  /// The slug the app currently shows; null when the link is REVOKED. Mismatch with the stored slug → 409
  @BuiltValueField(wireName: r'currentSlug')
  String? get currentSlug;

  BookingLinkMutationRequest._();

  factory BookingLinkMutationRequest(
          [void updates(BookingLinkMutationRequestBuilder b)]) =
      _$BookingLinkMutationRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingLinkMutationRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingLinkMutationRequest> get serializer =>
      _$BookingLinkMutationRequestSerializer();
}

class _$BookingLinkMutationRequestSerializer
    implements PrimitiveSerializer<BookingLinkMutationRequest> {
  @override
  final Iterable<Type> types = const [
    BookingLinkMutationRequest,
    _$BookingLinkMutationRequest
  ];

  @override
  final String wireName = r'BookingLinkMutationRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingLinkMutationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.currentSlug != null) {
      yield r'currentSlug';
      yield serializers.serialize(
        object.currentSlug,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingLinkMutationRequest object, {
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
    required BookingLinkMutationRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'currentSlug':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.currentSlug = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookingLinkMutationRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingLinkMutationRequestBuilder();
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
