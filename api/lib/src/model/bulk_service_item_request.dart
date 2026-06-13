//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bulk_service_item_request.g.dart';

/// BulkServiceItemRequest
///
/// Properties:
/// * [serviceTypeId]
/// * [durationMinutes]
/// * [priceType]
/// * [price]
/// * [priceMin]
/// * [priceMax]
@BuiltValue()
abstract class BulkServiceItemRequest
    implements Built<BulkServiceItemRequest, BulkServiceItemRequestBuilder> {
  @BuiltValueField(wireName: r'serviceTypeId')
  String get serviceTypeId;

  @BuiltValueField(wireName: r'durationMinutes')
  int get durationMinutes;

  @BuiltValueField(wireName: r'priceType')
  BulkServiceItemRequestPriceTypeEnum get priceType;
  // enum priceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'price')
  num? get price;

  @BuiltValueField(wireName: r'priceMin')
  num? get priceMin;

  @BuiltValueField(wireName: r'priceMax')
  num? get priceMax;

  BulkServiceItemRequest._();

  factory BulkServiceItemRequest(
          [void updates(BulkServiceItemRequestBuilder b)]) =
      _$BulkServiceItemRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BulkServiceItemRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BulkServiceItemRequest> get serializer =>
      _$BulkServiceItemRequestSerializer();
}

class _$BulkServiceItemRequestSerializer
    implements PrimitiveSerializer<BulkServiceItemRequest> {
  @override
  final Iterable<Type> types = const [
    BulkServiceItemRequest,
    _$BulkServiceItemRequest
  ];

  @override
  final String wireName = r'BulkServiceItemRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BulkServiceItemRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'serviceTypeId';
    yield serializers.serialize(
      object.serviceTypeId,
      specifiedType: const FullType(String),
    );
    yield r'durationMinutes';
    yield serializers.serialize(
      object.durationMinutes,
      specifiedType: const FullType(int),
    );
    yield r'priceType';
    yield serializers.serialize(
      object.priceType,
      specifiedType: const FullType(BulkServiceItemRequestPriceTypeEnum),
    );
    if (object.price != null) {
      yield r'price';
      yield serializers.serialize(
        object.price,
        specifiedType: const FullType(num),
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
        specifiedType: const FullType(num),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BulkServiceItemRequest object, {
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
    required BulkServiceItemRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'serviceTypeId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceTypeId = valueDes;
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
            specifiedType: const FullType(BulkServiceItemRequestPriceTypeEnum),
          ) as BulkServiceItemRequestPriceTypeEnum;
          result.priceType = valueDes;
          break;
        case r'price':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.price = valueDes;
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
            specifiedType: const FullType(num),
          ) as num;
          result.priceMax = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BulkServiceItemRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BulkServiceItemRequestBuilder();
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

class BulkServiceItemRequestPriceTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const BulkServiceItemRequestPriceTypeEnum FIXED =
      _$bulkServiceItemRequestPriceTypeEnum_FIXED;
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const BulkServiceItemRequestPriceTypeEnum RANGE =
      _$bulkServiceItemRequestPriceTypeEnum_RANGE;

  static Serializer<BulkServiceItemRequestPriceTypeEnum> get serializer =>
      _$bulkServiceItemRequestPriceTypeEnumSerializer;

  const BulkServiceItemRequestPriceTypeEnum._(String name) : super(name);

  static BuiltSet<BulkServiceItemRequestPriceTypeEnum> get values =>
      _$bulkServiceItemRequestPriceTypeEnumValues;
  static BulkServiceItemRequestPriceTypeEnum valueOf(String name) =>
      _$bulkServiceItemRequestPriceTypeEnumValueOf(name);
}
