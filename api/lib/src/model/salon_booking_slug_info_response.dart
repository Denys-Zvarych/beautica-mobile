//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/rating_bucket.dart';
import 'package:beautica_api/src/model/salon_review_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/media_file_response.dart';
import 'package:beautica_api/src/model/salon_booking_slug_master_item.dart';
import 'package:beautica_api/src/model/salon_service_category_group.dart';
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
/// * [region] - Settlement region label (salons.region).
/// * [street] - Street; falls back to the legacy free-text address when street is blank.
/// * [buildingNo]
/// * [updatedAt] - Salon last edited; display/JSON-LD only, never a cache validator.
/// * [description] - As PublicSalonResponse.description.
/// * [locationNote] - As PublicSalonResponse.locationNote.
/// * [portfolio] - Newest photos first, capped like the master page (12); the payload of GET /salons/{id}/portfolio.
/// * [serviceCategories] - Bookable services grouped by category — GET /salons/{id}/services, unchanged.
/// * [ratingDistribution] - Zero-filled 5..1 histogram — GET /salons/{id}/reviews/summary.
/// * [latestReviews] - The newest 5 reviews — the SalonReviewResponse rows of GET /salons/{id}/reviews.
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

  /// Settlement region label (salons.region).
  @BuiltValueField(wireName: r'region')
  String? get region;

  /// Street; falls back to the legacy free-text address when street is blank.
  @BuiltValueField(wireName: r'street')
  String? get street;

  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  /// Salon last edited; display/JSON-LD only, never a cache validator.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime get updatedAt;

  /// As PublicSalonResponse.description.
  @BuiltValueField(wireName: r'description')
  String? get description;

  /// As PublicSalonResponse.locationNote.
  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  /// Newest photos first, capped like the master page (12); the payload of GET /salons/{id}/portfolio.
  @BuiltValueField(wireName: r'portfolio')
  BuiltList<MediaFileResponse> get portfolio;

  /// Bookable services grouped by category — GET /salons/{id}/services, unchanged.
  @BuiltValueField(wireName: r'serviceCategories')
  BuiltList<SalonServiceCategoryGroup> get serviceCategories;

  /// Zero-filled 5..1 histogram — GET /salons/{id}/reviews/summary.
  @BuiltValueField(wireName: r'ratingDistribution')
  BuiltList<RatingBucket> get ratingDistribution;

  /// The newest 5 reviews — the SalonReviewResponse rows of GET /salons/{id}/reviews.
  @BuiltValueField(wireName: r'latestReviews')
  BuiltList<SalonReviewResponse> get latestReviews;

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
    if (object.region != null) {
      yield r'region';
      yield serializers.serialize(
        object.region,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.street != null) {
      yield r'street';
      yield serializers.serialize(
        object.street,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.buildingNo != null) {
      yield r'buildingNo';
      yield serializers.serialize(
        object.buildingNo,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'updatedAt';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.description != null) {
      yield r'description';
      yield serializers.serialize(
        object.description,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'portfolio';
    yield serializers.serialize(
      object.portfolio,
      specifiedType: const FullType(BuiltList, [FullType(MediaFileResponse)]),
    );
    yield r'serviceCategories';
    yield serializers.serialize(
      object.serviceCategories,
      specifiedType:
          const FullType(BuiltList, [FullType(SalonServiceCategoryGroup)]),
    );
    yield r'ratingDistribution';
    yield serializers.serialize(
      object.ratingDistribution,
      specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
    );
    yield r'latestReviews';
    yield serializers.serialize(
      object.latestReviews,
      specifiedType: const FullType(BuiltList, [FullType(SalonReviewResponse)]),
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
        case r'region':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.region = valueDes;
          break;
        case r'street':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.street = valueDes;
          break;
        case r'buildingNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.buildingNo = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.description = valueDes;
          break;
        case r'locationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.locationNote = valueDes;
          break;
        case r'portfolio':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(MediaFileResponse)]),
          ) as BuiltList<MediaFileResponse>;
          result.portfolio.replace(valueDes);
          break;
        case r'serviceCategories':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(
                BuiltList, [FullType(SalonServiceCategoryGroup)]),
          ) as BuiltList<SalonServiceCategoryGroup>;
          result.serviceCategories.replace(valueDes);
          break;
        case r'ratingDistribution':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
          ) as BuiltList<RatingBucket>;
          result.ratingDistribution.replace(valueDes);
          break;
        case r'latestReviews':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(SalonReviewResponse)]),
          ) as BuiltList<SalonReviewResponse>;
          result.latestReviews.replace(valueDes);
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
