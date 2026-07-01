//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/rating_bucket.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_review_summary_response.g.dart';

/// SalonReviewSummaryResponse
///
/// Properties:
/// * [avgRating]
/// * [reviewCount]
/// * [ratingDistribution]
@BuiltValue()
abstract class SalonReviewSummaryResponse
    implements
        Built<SalonReviewSummaryResponse, SalonReviewSummaryResponseBuilder> {
  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int? get reviewCount;

  @BuiltValueField(wireName: r'ratingDistribution')
  BuiltList<RatingBucket>? get ratingDistribution;

  SalonReviewSummaryResponse._();

  factory SalonReviewSummaryResponse(
          [void updates(SalonReviewSummaryResponseBuilder b)]) =
      _$SalonReviewSummaryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonReviewSummaryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonReviewSummaryResponse> get serializer =>
      _$SalonReviewSummaryResponseSerializer();
}

class _$SalonReviewSummaryResponseSerializer
    implements PrimitiveSerializer<SalonReviewSummaryResponse> {
  @override
  final Iterable<Type> types = const [
    SalonReviewSummaryResponse,
    _$SalonReviewSummaryResponse
  ];

  @override
  final String wireName = r'SalonReviewSummaryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonReviewSummaryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.avgRating != null) {
      yield r'avgRating';
      yield serializers.serialize(
        object.avgRating,
        specifiedType: const FullType(num),
      );
    }
    if (object.reviewCount != null) {
      yield r'reviewCount';
      yield serializers.serialize(
        object.reviewCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.ratingDistribution != null) {
      yield r'ratingDistribution';
      yield serializers.serialize(
        object.ratingDistribution,
        specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonReviewSummaryResponse object, {
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
    required SalonReviewSummaryResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'avgRating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.avgRating = valueDes;
          break;
        case r'reviewCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewCount = valueDes;
          break;
        case r'ratingDistribution':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
          ) as BuiltList<RatingBucket>;
          result.ratingDistribution.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonReviewSummaryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonReviewSummaryResponseBuilder();
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
