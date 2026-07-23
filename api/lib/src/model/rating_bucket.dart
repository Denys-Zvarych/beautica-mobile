//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rating_bucket.g.dart';

/// RatingBucket
///
/// Properties:
/// * [rating]
/// * [count]
@BuiltValue()
abstract class RatingBucket
    implements Built<RatingBucket, RatingBucketBuilder> {
  @BuiltValueField(wireName: r'rating')
  int? get rating;

  @BuiltValueField(wireName: r'count')
  int? get count;

  RatingBucket._();

  factory RatingBucket([void updates(RatingBucketBuilder b)]) = _$RatingBucket;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RatingBucketBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RatingBucket> get serializer => _$RatingBucketSerializer();
}

class _$RatingBucketSerializer implements PrimitiveSerializer<RatingBucket> {
  @override
  final Iterable<Type> types = const [RatingBucket, _$RatingBucket];

  @override
  final String wireName = r'RatingBucket';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RatingBucket object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.rating != null) {
      yield r'rating';
      yield serializers.serialize(
        object.rating,
        specifiedType: const FullType(int),
      );
    }
    if (object.count != null) {
      yield r'count';
      yield serializers.serialize(
        object.count,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RatingBucket object, {
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
    required RatingBucketBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rating = valueDes;
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RatingBucket deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RatingBucketBuilder();
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
