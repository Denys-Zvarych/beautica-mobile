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
/// * [sourceType] - Which favourite arm this row came from — MASTER (a chosen master's assignment) or SALON (a salon-catalogue service, no master chosen yet).
/// * [masterServiceId]
/// * [masterId]
/// * [serviceDefId]
/// * [serviceName]
/// * [masterFirstName]
/// * [masterLastName]
/// * [masterAvatarUrl] - users.avatar_url of the performing master; null when unset or for a SALON row.
/// * [durationMinutes]
/// * [priceType]
/// * [priceMin]
/// * [priceMax] - RANGE ceiling; null for FIXED.
/// * [priceDisplay] - Pre-formatted band, e.g. \"600 ₴\" or \"від 600 до 900 ₴\"; null only for a legacy definition with no price.
/// * [salonId] - salons.id — null for a MASTER row.
/// * [salonName] - salons.name — null for a MASTER row.
/// * [salonAvatarUrl] - salons.avatar_url — null for a MASTER row.
@BuiltValue()
abstract class FavoriteServiceResponse
    implements Built<FavoriteServiceResponse, FavoriteServiceResponseBuilder> {
  /// Which favourite arm this row came from — MASTER (a chosen master's assignment) or SALON (a salon-catalogue service, no master chosen yet).
  @BuiltValueField(wireName: r'sourceType')
  FavoriteServiceResponseSourceTypeEnum? get sourceType;
  // enum sourceTypeEnum {  MASTER,  SALON,  };

  @BuiltValueField(wireName: r'masterServiceId')
  String? get masterServiceId;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'serviceDefId')
  String? get serviceDefId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'masterFirstName')
  String? get masterFirstName;

  @BuiltValueField(wireName: r'masterLastName')
  String? get masterLastName;

  /// users.avatar_url of the performing master; null when unset or for a SALON row.
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

  /// salons.id — null for a MASTER row.
  @BuiltValueField(wireName: r'salonId')
  String? get salonId;

  /// salons.name — null for a MASTER row.
  @BuiltValueField(wireName: r'salonName')
  String? get salonName;

  /// salons.avatar_url — null for a MASTER row.
  @BuiltValueField(wireName: r'salonAvatarUrl')
  String? get salonAvatarUrl;

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
    if (object.sourceType != null) {
      yield r'sourceType';
      yield serializers.serialize(
        object.sourceType,
        specifiedType: const FullType(FavoriteServiceResponseSourceTypeEnum),
      );
    }
    if (object.masterServiceId != null) {
      yield r'masterServiceId';
      yield serializers.serialize(
        object.masterServiceId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.serviceDefId != null) {
      yield r'serviceDefId';
      yield serializers.serialize(
        object.serviceDefId,
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
    if (object.salonId != null) {
      yield r'salonId';
      yield serializers.serialize(
        object.salonId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.salonName != null) {
      yield r'salonName';
      yield serializers.serialize(
        object.salonName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.salonAvatarUrl != null) {
      yield r'salonAvatarUrl';
      yield serializers.serialize(
        object.salonAvatarUrl,
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
        case r'sourceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(FavoriteServiceResponseSourceTypeEnum),
          ) as FavoriteServiceResponseSourceTypeEnum;
          result.sourceType = valueDes;
          break;
        case r'masterServiceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.masterServiceId = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.masterId = valueDes;
          break;
        case r'serviceDefId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceDefId = valueDes;
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
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.salonId = valueDes;
          break;
        case r'salonName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.salonName = valueDes;
          break;
        case r'salonAvatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.salonAvatarUrl = valueDes;
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

class FavoriteServiceResponseSourceTypeEnum extends EnumClass {
  /// Which favourite arm this row came from — MASTER (a chosen master's assignment) or SALON (a salon-catalogue service, no master chosen yet).
  @BuiltValueEnumConst(wireName: r'MASTER')
  static const FavoriteServiceResponseSourceTypeEnum MASTER =
      _$favoriteServiceResponseSourceTypeEnum_MASTER;

  /// Which favourite arm this row came from — MASTER (a chosen master's assignment) or SALON (a salon-catalogue service, no master chosen yet).
  @BuiltValueEnumConst(wireName: r'SALON')
  static const FavoriteServiceResponseSourceTypeEnum SALON =
      _$favoriteServiceResponseSourceTypeEnum_SALON;

  static Serializer<FavoriteServiceResponseSourceTypeEnum> get serializer =>
      _$favoriteServiceResponseSourceTypeEnumSerializer;

  const FavoriteServiceResponseSourceTypeEnum._(String name) : super(name);

  static BuiltSet<FavoriteServiceResponseSourceTypeEnum> get values =>
      _$favoriteServiceResponseSourceTypeEnumValues;
  static FavoriteServiceResponseSourceTypeEnum valueOf(String name) =>
      _$favoriteServiceResponseSourceTypeEnumValueOf(name);
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
