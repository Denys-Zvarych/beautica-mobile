//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/review_invite_item_response.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_invite_response.g.dart';

/// ReviewInviteResponse
///
/// Properties:
/// * [state]
/// * [providerName]
/// * [providerType]
/// * [visitDate]
/// * [items]
/// * [displayName]
/// * [avatarUrl]
/// * [avgRating] - null while the provider has no reviews (never a fabricated 0).
/// * [reviewCount] - Set on every OPEN form (0 when none); absent on ALREADY_REVIEWED.
/// * [professionalTitle] - Master only; null for a salon.
@BuiltValue()
abstract class ReviewInviteResponse
    implements Built<ReviewInviteResponse, ReviewInviteResponseBuilder> {
  @BuiltValueField(wireName: r'state')
  String? get state;

  @BuiltValueField(wireName: r'providerName')
  String? get providerName;

  @BuiltValueField(wireName: r'providerType')
  String? get providerType;

  @BuiltValueField(wireName: r'visitDate')
  Date? get visitDate;

  @BuiltValueField(wireName: r'items')
  BuiltList<ReviewInviteItemResponse>? get items;

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  /// null while the provider has no reviews (never a fabricated 0).
  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  /// Set on every OPEN form (0 when none); absent on ALREADY_REVIEWED.
  @BuiltValueField(wireName: r'reviewCount')
  int? get reviewCount;

  /// Master only; null for a salon.
  @BuiltValueField(wireName: r'professionalTitle')
  String? get professionalTitle;

  ReviewInviteResponse._();

  factory ReviewInviteResponse([void updates(ReviewInviteResponseBuilder b)]) =
      _$ReviewInviteResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewInviteResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewInviteResponse> get serializer =>
      _$ReviewInviteResponseSerializer();
}

class _$ReviewInviteResponseSerializer
    implements PrimitiveSerializer<ReviewInviteResponse> {
  @override
  final Iterable<Type> types = const [
    ReviewInviteResponse,
    _$ReviewInviteResponse
  ];

  @override
  final String wireName = r'ReviewInviteResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewInviteResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.state != null) {
      yield r'state';
      yield serializers.serialize(
        object.state,
        specifiedType: const FullType(String),
      );
    }
    if (object.providerName != null) {
      yield r'providerName';
      yield serializers.serialize(
        object.providerName,
        specifiedType: const FullType(String),
      );
    }
    if (object.providerType != null) {
      yield r'providerType';
      yield serializers.serialize(
        object.providerType,
        specifiedType: const FullType(String),
      );
    }
    if (object.visitDate != null) {
      yield r'visitDate';
      yield serializers.serialize(
        object.visitDate,
        specifiedType: const FullType(Date),
      );
    }
    if (object.items != null) {
      yield r'items';
      yield serializers.serialize(
        object.items,
        specifiedType:
            const FullType(BuiltList, [FullType(ReviewInviteItemResponse)]),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
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
    if (object.reviewCount != null) {
      yield r'reviewCount';
      yield serializers.serialize(
        object.reviewCount,
        specifiedType: const FullType(int),
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
    ReviewInviteResponse object, {
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
    required ReviewInviteResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'providerName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.providerName = valueDes;
          break;
        case r'providerType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.providerType = valueDes;
          break;
        case r'visitDate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.visitDate = valueDes;
          break;
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ReviewInviteItemResponse)]),
          ) as BuiltList<ReviewInviteItemResponse>;
          result.items.replace(valueDes);
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.avatarUrl = valueDes;
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
  ReviewInviteResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewInviteResponseBuilder();
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
