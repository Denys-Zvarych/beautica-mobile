//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/booking_link_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_links_response.g.dart';

/// The caller's shareable public booking links
///
/// Properties:
/// * [shareEnabled] - Server kill-switch; false = sharing is hidden and links is empty
/// * [links] - MASTER link first, then SALON links by salon name
@BuiltValue()
abstract class BookingLinksResponse
    implements Built<BookingLinksResponse, BookingLinksResponseBuilder> {
  /// Server kill-switch; false = sharing is hidden and links is empty
  @BuiltValueField(wireName: r'shareEnabled')
  bool get shareEnabled;

  /// MASTER link first, then SALON links by salon name
  @BuiltValueField(wireName: r'links')
  BuiltList<BookingLinkResponse> get links;

  BookingLinksResponse._();

  factory BookingLinksResponse([void updates(BookingLinksResponseBuilder b)]) =
      _$BookingLinksResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingLinksResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingLinksResponse> get serializer =>
      _$BookingLinksResponseSerializer();
}

class _$BookingLinksResponseSerializer
    implements PrimitiveSerializer<BookingLinksResponse> {
  @override
  final Iterable<Type> types = const [
    BookingLinksResponse,
    _$BookingLinksResponse
  ];

  @override
  final String wireName = r'BookingLinksResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingLinksResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'shareEnabled';
    yield serializers.serialize(
      object.shareEnabled,
      specifiedType: const FullType(bool),
    );
    yield r'links';
    yield serializers.serialize(
      object.links,
      specifiedType: const FullType(BuiltList, [FullType(BookingLinkResponse)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingLinksResponse object, {
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
    required BookingLinksResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'shareEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.shareEnabled = valueDes;
          break;
        case r'links':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(BookingLinkResponse)]),
          ) as BuiltList<BookingLinkResponse>;
          result.links.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookingLinksResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingLinksResponseBuilder();
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
