//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'favorite_service_response.g.dart';

/// FavoriteServiceResponse
///
/// Properties:
/// * [masterServiceId]
/// * [masterId]
/// * [serviceName]
/// * [masterFirstName]
/// * [masterLastName]
/// * [masterAvatarUrl] - users.avatar_url of the performing master; null when unset.
/// * [durationMinutes]
/// * [priceType]
/// * [priceMin]
/// * [priceMax] - RANGE ceiling; null for FIXED.
/// * [priceDisplay] - Pre-formatted band, e.g. \"600 ₴\" or \"від 600 до 900 ₴\"; null only for a legacy definition with no price.
@BuiltValue()
abstract class FavoriteServiceResponse
    implements Built<FavoriteServiceResponse, FavoriteServiceResponseBuilder> {
  @BuiltValueField(wireName: r'masterServiceId')
  String? get masterServiceId;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'masterFirstName')
  String? get masterFirstName;

  @BuiltValueField(wireName: r'masterLastName')
  String? get masterLastName;

  /// users.avatar_url of the performing master; null when unset.
  @BuiltValueField(wireName: r'masterAvatarUrl')
  String? get masterAvatarUrl;

  @BuiltValueField(wireName: r'durationMinutes')
  int? get durationMinutes;

  @BuiltValueField(wireName: r'priceType')
  FavoriteServiceResponsePriceTypeEnum? get priceType;
  // enum priceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'priceMin')
  num? get priceMin;

  /// RANGE ceiling; null for FIXED.
  @BuiltValueField(wireName: r'priceMax')
  num? get priceMax;

  /// Pre-formatted band, e.g. \"600 ₴\" or \"від 600 до 900 ₴\"; null only for a legacy definition with no price.
  @BuiltValueField(wireName: r'priceDisplay')
  String? get priceDisplay;

  FavoriteServiceResponse._();

  factory FavoriteServiceResponse(
          [void updates(FavoriteServiceResponseBuilder b)]) =
      _$FavoriteServiceResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FavoriteServiceResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FavoriteServiceResponse> get serializer =>
      _$FavoriteServiceResponseSerializer();
}

class _$FavoriteServiceResponseSerializer
    implements PrimitiveSerializer<FavoriteServiceResponse> {
  @override
  final Iterable<Type> types = const [
    FavoriteServiceResponse,
    _$FavoriteServiceResponse
  ];

  @override
  final String wireName = r'FavoriteServiceResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FavoriteServiceResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterServiceId != null) {
      yield r'masterServiceId';
      yield serializers.serialize(
        object.masterServiceId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterFirstName != null) {
      yield r'masterFirstName';
      yield serializers.serialize(
        object.masterFirstName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.masterLastName != null) {
      yield r'masterLastName';
      yield serializers.serialize(
        object.masterLastName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.masterAvatarUrl != null) {
      yield r'masterAvatarUrl';
      yield serializers.serialize(
        object.masterAvatarUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.durationMinutes != null) {
      yield r'durationMinutes';
      yield serializers.serialize(
        object.durationMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.priceType != null) {
      yield r'priceType';
      yield serializers.serialize(
        object.priceType,
        specifiedType: const FullType(FavoriteServiceResponsePriceTypeEnum),
      );
    }
    if (object.priceMin != null) {
      yield r'priceMin';
      yield serializers.serialize(
        object.priceMin,
        specifiedType: const FullType(num),
      );
    }
    if (object.priceMax != null) {
      yield r'priceMax';
      yield serializers.serialize(
        object.priceMax,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.priceDisplay != null) {
      yield r'priceDisplay';
      yield serializers.serialize(
        object.priceDisplay,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FavoriteServiceResponse object, {
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
    required FavoriteServiceResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterServiceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterServiceId = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'masterFirstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.masterFirstName = valueDes;
          break;
        case r'masterLastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.masterLastName = valueDes;
          break;
        case r'masterAvatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.masterAvatarUrl = valueDes;
          break;
        case r'durationMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMinutes = valueDes;
          break;
        case r'priceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(FavoriteServiceResponsePriceTypeEnum),
          ) as FavoriteServiceResponsePriceTypeEnum;
          result.priceType = valueDes;
          break;
        case r'priceMin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.priceMin = valueDes;
          break;
        case r'priceMax':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.priceMax = valueDes;
          break;
        case r'priceDisplay':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.priceDisplay = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FavoriteServiceResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FavoriteServiceResponseBuilder();
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

class FavoriteServiceResponsePriceTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const FavoriteServiceResponsePriceTypeEnum FIXED =
      _$favoriteServiceResponsePriceTypeEnum_FIXED;
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const FavoriteServiceResponsePriceTypeEnum RANGE =
      _$favoriteServiceResponsePriceTypeEnum_RANGE;

  static Serializer<FavoriteServiceResponsePriceTypeEnum> get serializer =>
      _$favoriteServiceResponsePriceTypeEnumSerializer;

  const FavoriteServiceResponsePriceTypeEnum._(String name) : super(name);

  static BuiltSet<FavoriteServiceResponsePriceTypeEnum> get values =>
      _$favoriteServiceResponsePriceTypeEnumValues;
  static FavoriteServiceResponsePriceTypeEnum valueOf(String name) =>
      _$favoriteServiceResponsePriceTypeEnumValueOf(name);
}
