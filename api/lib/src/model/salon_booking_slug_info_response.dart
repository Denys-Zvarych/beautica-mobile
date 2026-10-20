//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/salon_booking_slug_master_item.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_booking_slug_info_response.g.dart';

/// SalonBookingSlugInfoResponse
///
/// Properties:
/// * [salonId]
/// * [name]
/// * [city] - Settlement display name (salons.city, denormalised from the taxonomy city).
/// * [avatarUrl]
/// * [coverImageUrl]
/// * [avgRating] - null while the salon has no reviews (never a fabricated 0).
/// * [reviewCount]
/// * [bookable] - false when no master of the salon is bookable yet; masters is then empty.
/// * [masters]
@BuiltValue()
abstract class SalonBookingSlugInfoResponse
    implements
        Built<SalonBookingSlugInfoResponse,
            SalonBookingSlugInfoResponseBuilder> {
  @BuiltValueField(wireName: r'salonId')
  String get salonId;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// Settlement display name (salons.city, denormalised from the taxonomy city).
  @BuiltValueField(wireName: r'city')
  String? get city;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'coverImageUrl')
  String? get coverImageUrl;

  /// null while the salon has no reviews (never a fabricated 0).
  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int get reviewCount;

  /// false when no master of the salon is bookable yet; masters is then empty.
  @BuiltValueField(wireName: r'bookable')
  bool get bookable;

  @BuiltValueField(wireName: r'masters')
  BuiltList<SalonBookingSlugMasterItem> get masters;

  SalonBookingSlugInfoResponse._();

  factory SalonBookingSlugInfoResponse(
          [void updates(SalonBookingSlugInfoResponseBuilder b)]) =
      _$SalonBookingSlugInfoResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonBookingSlugInfoResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonBookingSlugInfoResponse> get serializer =>
      _$SalonBookingSlugInfoResponseSerializer();
}

class _$SalonBookingSlugInfoResponseSerializer
    implements PrimitiveSerializer<SalonBookingSlugInfoResponse> {
  @override
  final Iterable<Type> types = const [
    SalonBookingSlugInfoResponse,
    _$SalonBookingSlugInfoResponse
  ];

  @override
  final String wireName = r'SalonBookingSlugInfoResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonBookingSlugInfoResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'salonId';
    yield serializers.serialize(
      object.salonId,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.city != null) {
      yield r'city';
      yield serializers.serialize(
        object.city,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.coverImageUrl != null) {
      yield r'coverImageUrl';
      yield serializers.serialize(
        object.coverImageUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.avgRating != null) {
      yield r'avgRating';
      yield serializers.serialize(
        object.avgRating,
        specifiedType: const FullType.nullable(num),
      );
    }
    yield r'reviewCount';
    yield serializers.serialize(
      object.reviewCount,
      specifiedType: const FullType(int),
    );
    yield r'bookable';
    yield serializers.serialize(
      object.bookable,
      specifiedType: const FullType(bool),
    );
    yield r'masters';
    yield serializers.serialize(
      object.masters,
      specifiedType:
          const FullType(BuiltList, [FullType(SalonBookingSlugMasterItem)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonBookingSlugInfoResponse object, {
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
    required SalonBookingSlugInfoResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.salonId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'city':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.city = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.avatarUrl = valueDes;
          break;
        case r'coverImageUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.coverImageUrl = valueDes;
          break;
        case r'avgRating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.avgRating = valueDes;
          break;
        case r'reviewCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewCount = valueDes;
          break;
        case r'bookable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.bookable = valueDes;
          break;
        case r'masters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(
                BuiltList, [FullType(SalonBookingSlugMasterItem)]),
          ) as BuiltList<SalonBookingSlugMasterItem>;
          result.masters.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonBookingSlugInfoResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonBookingSlugInfoResponseBuilder();
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
