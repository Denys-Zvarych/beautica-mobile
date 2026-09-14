//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_master_service_band_request.g.dart';

/// UpdateMasterServiceBandRequest
///
/// Properties:
/// * [priceType]
/// * [price]
/// * [priceMax]
/// * [durationOverrideMinutes]
/// * [clearBand]
/// * [clearDurationOverride]
/// * [notEmpty]
/// * [clearBandCoherent]
/// * [clearDurationOverrideCoherent]
/// * [bandLegal]
@BuiltValue()
abstract class UpdateMasterServiceBandRequest
    implements
        Built<UpdateMasterServiceBandRequest,
            UpdateMasterServiceBandRequestBuilder> {
  @BuiltValueField(wireName: r'priceType')
  UpdateMasterServiceBandRequestPriceTypeEnum? get priceType;
  // enum priceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'price')
  num? get price;

  @BuiltValueField(wireName: r'priceMax')
  num? get priceMax;

  @BuiltValueField(wireName: r'durationOverrideMinutes')
  int? get durationOverrideMinutes;

  @BuiltValueField(wireName: r'clearBand')
  bool? get clearBand;

  @BuiltValueField(wireName: r'clearDurationOverride')
  bool? get clearDurationOverride;

  @BuiltValueField(wireName: r'notEmpty')
  bool? get notEmpty;

  @BuiltValueField(wireName: r'clearBandCoherent')
  bool? get clearBandCoherent;

  @BuiltValueField(wireName: r'clearDurationOverrideCoherent')
  bool? get clearDurationOverrideCoherent;

  @BuiltValueField(wireName: r'bandLegal')
  bool? get bandLegal;

  UpdateMasterServiceBandRequest._();

  factory UpdateMasterServiceBandRequest(
          [void updates(UpdateMasterServiceBandRequestBuilder b)]) =
      _$UpdateMasterServiceBandRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateMasterServiceBandRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateMasterServiceBandRequest> get serializer =>
      _$UpdateMasterServiceBandRequestSerializer();
}

class _$UpdateMasterServiceBandRequestSerializer
    implements PrimitiveSerializer<UpdateMasterServiceBandRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateMasterServiceBandRequest,
    _$UpdateMasterServiceBandRequest
  ];

  @override
  final String wireName = r'UpdateMasterServiceBandRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateMasterServiceBandRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.priceType != null) {
      yield r'priceType';
      yield serializers.serialize(
        object.priceType,
        specifiedType:
            const FullType(UpdateMasterServiceBandRequestPriceTypeEnum),
      );
    }
    if (object.price != null) {
      yield r'price';
      yield serializers.serialize(
        object.price,
        specifiedType: const FullType(num),
      );
    }
    if (object.priceMax != null) {
      yield r'priceMax';
      yield serializers.serialize(
        object.priceMax,
        specifiedType: const FullType(num),
      );
    }
    if (object.durationOverrideMinutes != null) {
      yield r'durationOverrideMinutes';
      yield serializers.serialize(
        object.durationOverrideMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.clearBand != null) {
      yield r'clearBand';
      yield serializers.serialize(
        object.clearBand,
        specifiedType: const FullType(bool),
      );
    }
    if (object.clearDurationOverride != null) {
      yield r'clearDurationOverride';
      yield serializers.serialize(
        object.clearDurationOverride,
        specifiedType: const FullType(bool),
      );
    }
    if (object.notEmpty != null) {
      yield r'notEmpty';
      yield serializers.serialize(
        object.notEmpty,
        specifiedType: const FullType(bool),
      );
    }
    if (object.clearBandCoherent != null) {
      yield r'clearBandCoherent';
      yield serializers.serialize(
        object.clearBandCoherent,
        specifiedType: const FullType(bool),
      );
    }
    if (object.clearDurationOverrideCoherent != null) {
      yield r'clearDurationOverrideCoherent';
      yield serializers.serialize(
        object.clearDurationOverrideCoherent,
        specifiedType: const FullType(bool),
      );
    }
    if (object.bandLegal != null) {
      yield r'bandLegal';
      yield serializers.serialize(
        object.bandLegal,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateMasterServiceBandRequest object, {
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
    required UpdateMasterServiceBandRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'priceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(UpdateMasterServiceBandRequestPriceTypeEnum),
          ) as UpdateMasterServiceBandRequestPriceTypeEnum;
          result.priceType = valueDes;
          break;
        case r'price':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.price = valueDes;
          break;
        case r'priceMax':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.priceMax = valueDes;
          break;
        case r'durationOverrideMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationOverrideMinutes = valueDes;
          break;
        case r'clearBand':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.clearBand = valueDes;
          break;
        case r'clearDurationOverride':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.clearDurationOverride = valueDes;
          break;
        case r'notEmpty':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.notEmpty = valueDes;
          break;
        case r'clearBandCoherent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.clearBandCoherent = valueDes;
          break;
        case r'clearDurationOverrideCoherent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.clearDurationOverrideCoherent = valueDes;
          break;
        case r'bandLegal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.bandLegal = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateMasterServiceBandRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateMasterServiceBandRequestBuilder();
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

class UpdateMasterServiceBandRequestPriceTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const UpdateMasterServiceBandRequestPriceTypeEnum FIXED =
      _$updateMasterServiceBandRequestPriceTypeEnum_FIXED;
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const UpdateMasterServiceBandRequestPriceTypeEnum RANGE =
      _$updateMasterServiceBandRequestPriceTypeEnum_RANGE;

  static Serializer<UpdateMasterServiceBandRequestPriceTypeEnum>
      get serializer => _$updateMasterServiceBandRequestPriceTypeEnumSerializer;

  const UpdateMasterServiceBandRequestPriceTypeEnum._(String name)
      : super(name);

  static BuiltSet<UpdateMasterServiceBandRequestPriceTypeEnum> get values =>
      _$updateMasterServiceBandRequestPriceTypeEnumValues;
  static UpdateMasterServiceBandRequestPriceTypeEnum valueOf(String name) =>
      _$updateMasterServiceBandRequestPriceTypeEnumValueOf(name);
}
