//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'assign_service_to_master_request.g.dart';

/// AssignServiceToMasterRequest
///
/// Properties:
/// * [serviceDefId]
/// * [priceType]
/// * [priceOverride]
/// * [priceMax]
/// * [durationOverrideMinutes]
/// * [bandLegal]
@BuiltValue()
abstract class AssignServiceToMasterRequest
    implements
        Built<AssignServiceToMasterRequest,
            AssignServiceToMasterRequestBuilder> {
  @BuiltValueField(wireName: r'serviceDefId')
  String get serviceDefId;

  @BuiltValueField(wireName: r'priceType')
  AssignServiceToMasterRequestPriceTypeEnum? get priceType;
  // enum priceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'priceOverride')
  num? get priceOverride;

  @BuiltValueField(wireName: r'priceMax')
  num? get priceMax;

  @BuiltValueField(wireName: r'durationOverrideMinutes')
  int? get durationOverrideMinutes;

  @BuiltValueField(wireName: r'bandLegal')
  bool? get bandLegal;

  AssignServiceToMasterRequest._();

  factory AssignServiceToMasterRequest(
          [void updates(AssignServiceToMasterRequestBuilder b)]) =
      _$AssignServiceToMasterRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AssignServiceToMasterRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AssignServiceToMasterRequest> get serializer =>
      _$AssignServiceToMasterRequestSerializer();
}

class _$AssignServiceToMasterRequestSerializer
    implements PrimitiveSerializer<AssignServiceToMasterRequest> {
  @override
  final Iterable<Type> types = const [
    AssignServiceToMasterRequest,
    _$AssignServiceToMasterRequest
  ];

  @override
  final String wireName = r'AssignServiceToMasterRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AssignServiceToMasterRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'serviceDefId';
    yield serializers.serialize(
      object.serviceDefId,
      specifiedType: const FullType(String),
    );
    if (object.priceType != null) {
      yield r'priceType';
      yield serializers.serialize(
        object.priceType,
        specifiedType:
            const FullType(AssignServiceToMasterRequestPriceTypeEnum),
      );
    }
    if (object.priceOverride != null) {
      yield r'priceOverride';
      yield serializers.serialize(
        object.priceOverride,
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
    AssignServiceToMasterRequest object, {
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
    required AssignServiceToMasterRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'serviceDefId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceDefId = valueDes;
          break;
        case r'priceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(AssignServiceToMasterRequestPriceTypeEnum),
          ) as AssignServiceToMasterRequestPriceTypeEnum;
          result.priceType = valueDes;
          break;
        case r'priceOverride':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.priceOverride = valueDes;
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
  AssignServiceToMasterRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AssignServiceToMasterRequestBuilder();
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

class AssignServiceToMasterRequestPriceTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const AssignServiceToMasterRequestPriceTypeEnum FIXED =
      _$assignServiceToMasterRequestPriceTypeEnum_FIXED;
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const AssignServiceToMasterRequestPriceTypeEnum RANGE =
      _$assignServiceToMasterRequestPriceTypeEnum_RANGE;

  static Serializer<AssignServiceToMasterRequestPriceTypeEnum> get serializer =>
      _$assignServiceToMasterRequestPriceTypeEnumSerializer;

  const AssignServiceToMasterRequestPriceTypeEnum._(String name) : super(name);

  static BuiltSet<AssignServiceToMasterRequestPriceTypeEnum> get values =>
      _$assignServiceToMasterRequestPriceTypeEnumValues;
  static AssignServiceToMasterRequestPriceTypeEnum valueOf(String name) =>
      _$assignServiceToMasterRequestPriceTypeEnumValueOf(name);
}
