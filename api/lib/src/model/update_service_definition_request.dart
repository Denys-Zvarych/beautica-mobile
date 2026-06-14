//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_service_definition_request.g.dart';

/// UpdateServiceDefinitionRequest
///
/// Properties:
/// * [name]
/// * [description]
/// * [category]
/// * [baseDurationMinutes]
/// * [bufferMinutesAfter]
/// * [priceType]
/// * [price]
/// * [priceMin]
/// * [priceMax]
/// * [serviceTypeId] - Optional id of the platform service type to switch this service to. Omit or send null to leave the current service type unchanged.
@BuiltValue()
abstract class UpdateServiceDefinitionRequest
    implements
        Built<UpdateServiceDefinitionRequest,
            UpdateServiceDefinitionRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'description')
  String? get description;

  @BuiltValueField(wireName: r'category')
  String? get category;

  @BuiltValueField(wireName: r'baseDurationMinutes')
  int? get baseDurationMinutes;

  @BuiltValueField(wireName: r'bufferMinutesAfter')
  int? get bufferMinutesAfter;

  @BuiltValueField(wireName: r'priceType')
  UpdateServiceDefinitionRequestPriceTypeEnum? get priceType;
  // enum priceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'price')
  num? get price;

  @BuiltValueField(wireName: r'priceMin')
  num? get priceMin;

  @BuiltValueField(wireName: r'priceMax')
  num? get priceMax;

  /// Optional id of the platform service type to switch this service to. Omit or send null to leave the current service type unchanged.
  @BuiltValueField(wireName: r'serviceTypeId')
  String? get serviceTypeId;

  UpdateServiceDefinitionRequest._();

  factory UpdateServiceDefinitionRequest(
          [void updates(UpdateServiceDefinitionRequestBuilder b)]) =
      _$UpdateServiceDefinitionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateServiceDefinitionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateServiceDefinitionRequest> get serializer =>
      _$UpdateServiceDefinitionRequestSerializer();
}

class _$UpdateServiceDefinitionRequestSerializer
    implements PrimitiveSerializer<UpdateServiceDefinitionRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateServiceDefinitionRequest,
    _$UpdateServiceDefinitionRequest
  ];

  @override
  final String wireName = r'UpdateServiceDefinitionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateServiceDefinitionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    if (object.description != null) {
      yield r'description';
      yield serializers.serialize(
        object.description,
        specifiedType: const FullType(String),
      );
    }
    if (object.category != null) {
      yield r'category';
      yield serializers.serialize(
        object.category,
        specifiedType: const FullType(String),
      );
    }
    if (object.baseDurationMinutes != null) {
      yield r'baseDurationMinutes';
      yield serializers.serialize(
        object.baseDurationMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.bufferMinutesAfter != null) {
      yield r'bufferMinutesAfter';
      yield serializers.serialize(
        object.bufferMinutesAfter,
        specifiedType: const FullType(int),
      );
    }
    if (object.priceType != null) {
      yield r'priceType';
      yield serializers.serialize(
        object.priceType,
        specifiedType:
            const FullType(UpdateServiceDefinitionRequestPriceTypeEnum),
      );
    }
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
    if (object.serviceTypeId != null) {
      yield r'serviceTypeId';
      yield serializers.serialize(
        object.serviceTypeId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateServiceDefinitionRequest object, {
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
    required UpdateServiceDefinitionRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.category = valueDes;
          break;
        case r'baseDurationMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.baseDurationMinutes = valueDes;
          break;
        case r'bufferMinutesAfter':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bufferMinutesAfter = valueDes;
          break;
        case r'priceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(UpdateServiceDefinitionRequestPriceTypeEnum),
          ) as UpdateServiceDefinitionRequestPriceTypeEnum;
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
        case r'serviceTypeId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.serviceTypeId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateServiceDefinitionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateServiceDefinitionRequestBuilder();
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

class UpdateServiceDefinitionRequestPriceTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const UpdateServiceDefinitionRequestPriceTypeEnum FIXED =
      _$updateServiceDefinitionRequestPriceTypeEnum_FIXED;
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const UpdateServiceDefinitionRequestPriceTypeEnum RANGE =
      _$updateServiceDefinitionRequestPriceTypeEnum_RANGE;

  static Serializer<UpdateServiceDefinitionRequestPriceTypeEnum>
      get serializer => _$updateServiceDefinitionRequestPriceTypeEnumSerializer;

  const UpdateServiceDefinitionRequestPriceTypeEnum._(String name)
      : super(name);

  static BuiltSet<UpdateServiceDefinitionRequestPriceTypeEnum> get values =>
      _$updateServiceDefinitionRequestPriceTypeEnumValues;
  static UpdateServiceDefinitionRequestPriceTypeEnum valueOf(String name) =>
      _$updateServiceDefinitionRequestPriceTypeEnumValueOf(name);
}
