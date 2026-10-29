//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_invite_item_response.g.dart';

/// ReviewInviteItemResponse
///
/// Properties:
/// * [bookingId]
/// * [serviceName]
/// * [masterName]
@BuiltValue()
abstract class ReviewInviteItemResponse
    implements
        Built<ReviewInviteItemResponse, ReviewInviteItemResponseBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'masterName')
  String? get masterName;

  ReviewInviteItemResponse._();

  factory ReviewInviteItemResponse(
          [void updates(ReviewInviteItemResponseBuilder b)]) =
      _$ReviewInviteItemResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewInviteItemResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewInviteItemResponse> get serializer =>
      _$ReviewInviteItemResponseSerializer();
}

class _$ReviewInviteItemResponseSerializer
    implements PrimitiveSerializer<ReviewInviteItemResponse> {
  @override
  final Iterable<Type> types = const [
    ReviewInviteItemResponse,
    _$ReviewInviteItemResponse
  ];

  @override
  final String wireName = r'ReviewInviteItemResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewInviteItemResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.bookingId != null) {
      yield r'bookingId';
      yield serializers.serialize(
        object.bookingId,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterName != null) {
      yield r'masterName';
      yield serializers.serialize(
        object.masterName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewInviteItemResponse object, {
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
    required ReviewInviteItemResponseBuilder result,
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
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'masterName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewInviteItemResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewInviteItemResponseBuilder();
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
