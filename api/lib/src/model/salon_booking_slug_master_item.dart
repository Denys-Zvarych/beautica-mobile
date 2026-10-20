//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_booking_slug_master_item.g.dart';

/// SalonBookingSlugMasterItem
///
/// Properties:
/// * [masterSlug] - The master's public booking slug; use it with GET /api/v1/book/{slug}/info, /availability and /booking.
/// * [name] - Composed \"First Last\".
/// * [avatarUrl]
/// * [professionalTitle]
@BuiltValue()
abstract class SalonBookingSlugMasterItem
    implements
        Built<SalonBookingSlugMasterItem, SalonBookingSlugMasterItemBuilder> {
  /// The master's public booking slug; use it with GET /api/v1/book/{slug}/info, /availability and /booking.
  @BuiltValueField(wireName: r'masterSlug')
  String get masterSlug;

  /// Composed \"First Last\".
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'professionalTitle')
  String? get professionalTitle;

  SalonBookingSlugMasterItem._();

  factory SalonBookingSlugMasterItem(
          [void updates(SalonBookingSlugMasterItemBuilder b)]) =
      _$SalonBookingSlugMasterItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonBookingSlugMasterItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonBookingSlugMasterItem> get serializer =>
      _$SalonBookingSlugMasterItemSerializer();
}

class _$SalonBookingSlugMasterItemSerializer
    implements PrimitiveSerializer<SalonBookingSlugMasterItem> {
  @override
  final Iterable<Type> types = const [
    SalonBookingSlugMasterItem,
    _$SalonBookingSlugMasterItem
  ];

  @override
  final String wireName = r'SalonBookingSlugMasterItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonBookingSlugMasterItem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'masterSlug';
    yield serializers.serialize(
      object.masterSlug,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.professionalTitle != null) {
      yield r'professionalTitle';
      yield serializers.serialize(
        object.professionalTitle,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonBookingSlugMasterItem object, {
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
    required SalonBookingSlugMasterItemBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterSlug':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterSlug = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.avatarUrl = valueDes;
          break;
        case r'professionalTitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.professionalTitle = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonBookingSlugMasterItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonBookingSlugMasterItemBuilder();
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
