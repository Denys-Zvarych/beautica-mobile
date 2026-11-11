//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_cancel_request.g.dart';

/// GuestCancelRequest
///
/// Properties:
/// * [bookingIds]
@BuiltValue()
abstract class GuestCancelRequest
    implements Built<GuestCancelRequest, GuestCancelRequestBuilder> {
  @BuiltValueField(wireName: r'bookingIds')
  BuiltList<String>? get bookingIds;

  GuestCancelRequest._();

  factory GuestCancelRequest([void updates(GuestCancelRequestBuilder b)]) =
      _$GuestCancelRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestCancelRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestCancelRequest> get serializer =>
      _$GuestCancelRequestSerializer();
}

class _$GuestCancelRequestSerializer
    implements PrimitiveSerializer<GuestCancelRequest> {
  @override
  final Iterable<Type> types = const [GuestCancelRequest, _$GuestCancelRequest];

  @override
  final String wireName = r'GuestCancelRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestCancelRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.bookingIds != null) {
      yield r'bookingIds';
      yield serializers.serialize(
        object.bookingIds,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestCancelRequest object, {
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
    required GuestCancelRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bookingIds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.bookingIds.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestCancelRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestCancelRequestBuilder();
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
