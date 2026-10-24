//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_slug_salon_ref.g.dart';

/// BookingSlugSalonRef
///
/// Properties:
/// * [name]
/// * [bookingSlug]
@BuiltValue()
abstract class BookingSlugSalonRef
    implements Built<BookingSlugSalonRef, BookingSlugSalonRefBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'bookingSlug')
  String? get bookingSlug;

  BookingSlugSalonRef._();

  factory BookingSlugSalonRef([void updates(BookingSlugSalonRefBuilder b)]) =
      _$BookingSlugSalonRef;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingSlugSalonRefBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingSlugSalonRef> get serializer =>
      _$BookingSlugSalonRefSerializer();
}

class _$BookingSlugSalonRefSerializer
    implements PrimitiveSerializer<BookingSlugSalonRef> {
  @override
  final Iterable<Type> types = const [
    BookingSlugSalonRef,
    _$BookingSlugSalonRef
  ];

  @override
  final String wireName = r'BookingSlugSalonRef';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingSlugSalonRef object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.bookingSlug != null) {
      yield r'bookingSlug';
      yield serializers.serialize(
        object.bookingSlug,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingSlugSalonRef object, {
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
    required BookingSlugSalonRefBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'bookingSlug':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.bookingSlug = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookingSlugSalonRef deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingSlugSalonRefBuilder();
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
