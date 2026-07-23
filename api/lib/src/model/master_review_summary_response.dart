//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/rating_bucket.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'master_review_summary_response.g.dart';

/// MasterReviewSummaryResponse
///
/// Properties:
/// * [avgRating]
/// * [reviewCount]
/// * [ratingDistribution]
@BuiltValue()
abstract class MasterReviewSummaryResponse
    implements
        Built<MasterReviewSummaryResponse, MasterReviewSummaryResponseBuilder> {
  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int? get reviewCount;

  @BuiltValueField(wireName: r'ratingDistribution')
  BuiltList<RatingBucket>? get ratingDistribution;

  MasterReviewSummaryResponse._();

  factory MasterReviewSummaryResponse(
          [void updates(MasterReviewSummaryResponseBuilder b)]) =
      _$MasterReviewSummaryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MasterReviewSummaryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MasterReviewSummaryResponse> get serializer =>
      _$MasterReviewSummaryResponseSerializer();
}

class _$MasterReviewSummaryResponseSerializer
    implements PrimitiveSerializer<MasterReviewSummaryResponse> {
  @override
  final Iterable<Type> types = const [
    MasterReviewSummaryResponse,
    _$MasterReviewSummaryResponse
  ];

  @override
  final String wireName = r'MasterReviewSummaryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MasterReviewSummaryResponse object, {
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
    MasterReviewSummaryResponse object, {
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
    required MasterReviewSummaryResponseBuilder result,
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
  MasterReviewSummaryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MasterReviewSummaryResponseBuilder();
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
