//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/review_response.dart';
import 'package:beautica_api/src/model/booking_slug_salon_ref.dart';
import 'package:beautica_api/src/model/rating_bucket.dart';
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/media_file_response.dart';
import 'package:beautica_api/src/model/service_summary_dto.dart';
import 'package:beautica_api/src/model/category_ref.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_slug_info_response.g.dart';

/// BookingSlugInfoResponse
///
/// Properties:
/// * [masterName]
/// * [avatarUrl]
/// * [bio]
/// * [services]
/// * [masterId]
/// * [masterType]
/// * [professionalTitle]
/// * [city]
/// * [region]
/// * [salon] - null for independent masters.
/// * [avgRating] - null while the master has no reviews (never a fabricated 0).
/// * [reviewCount]
/// * [categories]
/// * [portfolio]
/// * [latestReviews]
/// * [bookable] - false when the master has no active service or no working schedule yet; the page then renders «not accepting online bookings».
/// * [updatedAt] - Profile last edited; display/JSON-LD only, never a cache validator.
/// * [ratingDistribution] - Zero-filled 5..1 histogram, the same as GET /masters/{id}/reviews/summary (phase 383).
/// * [street] - Non-null only for INDEPENDENT_MASTER (the app's public-profile address rule).
/// * [buildingNo] - Non-null only for INDEPENDENT_MASTER.
/// * [locationNote] - Non-null only for INDEPENDENT_MASTER.
@BuiltValue()
abstract class BookingSlugInfoResponse
    implements Built<BookingSlugInfoResponse, BookingSlugInfoResponseBuilder> {
  @BuiltValueField(wireName: r'masterName')
  String get masterName;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'bio')
  String? get bio;

  @BuiltValueField(wireName: r'services')
  BuiltList<ServiceSummaryDto> get services;

  @BuiltValueField(wireName: r'masterId')
  String get masterId;

  @BuiltValueField(wireName: r'masterType')
  BookingSlugInfoResponseMasterTypeEnum get masterType;
  // enum masterTypeEnum {  SALON_MASTER,  INDEPENDENT_MASTER,  SALON_OWNER,  };

  @BuiltValueField(wireName: r'professionalTitle')
  String? get professionalTitle;

  @BuiltValueField(wireName: r'city')
  String? get city;

  @BuiltValueField(wireName: r'region')
  String? get region;

  /// null for independent masters.
  @BuiltValueField(wireName: r'salon')
  BookingSlugSalonRef? get salon;

  /// null while the master has no reviews (never a fabricated 0).
  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int get reviewCount;

  @BuiltValueField(wireName: r'categories')
  BuiltList<CategoryRef> get categories;

  @BuiltValueField(wireName: r'portfolio')
  BuiltList<MediaFileResponse> get portfolio;

  @BuiltValueField(wireName: r'latestReviews')
  BuiltList<ReviewResponse> get latestReviews;

  /// false when the master has no active service or no working schedule yet; the page then renders «not accepting online bookings».
  @BuiltValueField(wireName: r'bookable')
  bool get bookable;

  /// Profile last edited; display/JSON-LD only, never a cache validator.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime get updatedAt;

  /// Zero-filled 5..1 histogram, the same as GET /masters/{id}/reviews/summary (phase 383).
  @BuiltValueField(wireName: r'ratingDistribution')
  BuiltList<RatingBucket> get ratingDistribution;

  /// Non-null only for INDEPENDENT_MASTER (the app's public-profile address rule).
  @BuiltValueField(wireName: r'street')
  String? get street;

  /// Non-null only for INDEPENDENT_MASTER.
  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  /// Non-null only for INDEPENDENT_MASTER.
  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  BookingSlugInfoResponse._();

  factory BookingSlugInfoResponse(
          [void updates(BookingSlugInfoResponseBuilder b)]) =
      _$BookingSlugInfoResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingSlugInfoResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingSlugInfoResponse> get serializer =>
      _$BookingSlugInfoResponseSerializer();
}

class _$BookingSlugInfoResponseSerializer
    implements PrimitiveSerializer<BookingSlugInfoResponse> {
  @override
  final Iterable<Type> types = const [
    BookingSlugInfoResponse,
    _$BookingSlugInfoResponse
  ];

  @override
  final String wireName = r'BookingSlugInfoResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingSlugInfoResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'masterName';
    yield serializers.serialize(
      object.masterName,
      specifiedType: const FullType(String),
    );
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.bio != null) {
      yield r'bio';
      yield serializers.serialize(
        object.bio,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'services';
    yield serializers.serialize(
      object.services,
      specifiedType: const FullType(BuiltList, [FullType(ServiceSummaryDto)]),
    );
    yield r'masterId';
    yield serializers.serialize(
      object.masterId,
      specifiedType: const FullType(String),
    );
    yield r'masterType';
    yield serializers.serialize(
      object.masterType,
      specifiedType: const FullType(BookingSlugInfoResponseMasterTypeEnum),
    );
    if (object.professionalTitle != null) {
      yield r'professionalTitle';
      yield serializers.serialize(
        object.professionalTitle,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.city != null) {
      yield r'city';
      yield serializers.serialize(
        object.city,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.region != null) {
      yield r'region';
      yield serializers.serialize(
        object.region,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.salon != null) {
      yield r'salon';
      yield serializers.serialize(
        object.salon,
        specifiedType: const FullType(BookingSlugSalonRef),
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
    yield r'categories';
    yield serializers.serialize(
      object.categories,
      specifiedType: const FullType(BuiltList, [FullType(CategoryRef)]),
    );
    yield r'portfolio';
    yield serializers.serialize(
      object.portfolio,
      specifiedType: const FullType(BuiltList, [FullType(MediaFileResponse)]),
    );
    yield r'latestReviews';
    yield serializers.serialize(
      object.latestReviews,
      specifiedType: const FullType(BuiltList, [FullType(ReviewResponse)]),
    );
    yield r'bookable';
    yield serializers.serialize(
      object.bookable,
      specifiedType: const FullType(bool),
    );
    yield r'updatedAt';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'ratingDistribution';
    yield serializers.serialize(
      object.ratingDistribution,
      specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
    );
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
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingSlugInfoResponse object, {
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
    required BookingSlugInfoResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterName = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.avatarUrl = valueDes;
          break;
        case r'bio':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.bio = valueDes;
          break;
        case r'services':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ServiceSummaryDto)]),
          ) as BuiltList<ServiceSummaryDto>;
          result.services.replace(valueDes);
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'masterType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BookingSlugInfoResponseMasterTypeEnum),
          ) as BookingSlugInfoResponseMasterTypeEnum;
          result.masterType = valueDes;
          break;
        case r'professionalTitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.professionalTitle = valueDes;
          break;
        case r'city':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.city = valueDes;
          break;
        case r'region':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.region = valueDes;
          break;
        case r'salon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingSlugSalonRef),
          ) as BookingSlugSalonRef;
          result.salon.replace(valueDes);
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
        case r'categories':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CategoryRef)]),
          ) as BuiltList<CategoryRef>;
          result.categories.replace(valueDes);
          break;
        case r'portfolio':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(MediaFileResponse)]),
          ) as BuiltList<MediaFileResponse>;
          result.portfolio.replace(valueDes);
          break;
        case r'latestReviews':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ReviewResponse)]),
          ) as BuiltList<ReviewResponse>;
          result.latestReviews.replace(valueDes);
          break;
        case r'bookable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.bookable = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        case r'ratingDistribution':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
          ) as BuiltList<RatingBucket>;
          result.ratingDistribution.replace(valueDes);
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
        case r'locationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.locationNote = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookingSlugInfoResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingSlugInfoResponseBuilder();
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

class BookingSlugInfoResponseMasterTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const BookingSlugInfoResponseMasterTypeEnum SALON_MASTER =
      _$bookingSlugInfoResponseMasterTypeEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const BookingSlugInfoResponseMasterTypeEnum INDEPENDENT_MASTER =
      _$bookingSlugInfoResponseMasterTypeEnum_INDEPENDENT_MASTER;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const BookingSlugInfoResponseMasterTypeEnum SALON_OWNER =
      _$bookingSlugInfoResponseMasterTypeEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const BookingSlugInfoResponseMasterTypeEnum unknownDefaultOpenApi =
      _$bookingSlugInfoResponseMasterTypeEnum_unknownDefaultOpenApi;

  static Serializer<BookingSlugInfoResponseMasterTypeEnum> get serializer =>
      _$bookingSlugInfoResponseMasterTypeEnumSerializer;

  const BookingSlugInfoResponseMasterTypeEnum._(String name) : super(name);

  static BuiltSet<BookingSlugInfoResponseMasterTypeEnum> get values =>
      _$bookingSlugInfoResponseMasterTypeEnumValues;
  static BookingSlugInfoResponseMasterTypeEnum valueOf(String name) =>
      _$bookingSlugInfoResponseMasterTypeEnumValueOf(name);
}
