//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/service_definition_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'master_service_response.g.dart';

/// MasterServiceResponse
///
/// Properties:
/// * [id]
/// * [masterId]
/// * [serviceDefinition]
/// * [priceOverride]
/// * [durationOverrideMinutes]
/// * [effectivePrice]
/// * [effectiveDurationMinutes]
/// * [isActive]
/// * [priceType]
/// * [priceMin]
/// * [priceMax]
/// * [priceDisplay]
/// * [serviceTypeId] - Chosen service type id; null when no service type was selected.
/// * [serviceTypeNameUk] - Ukrainian display name of the chosen service type; null when none was selected.
@BuiltValue()
abstract class MasterServiceResponse
    implements Built<MasterServiceResponse, MasterServiceResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'serviceDefinition')
  ServiceDefinitionResponse? get serviceDefinition;

  @BuiltValueField(wireName: r'priceOverride')
  num? get priceOverride;

  @BuiltValueField(wireName: r'durationOverrideMinutes')
  int? get durationOverrideMinutes;

  @BuiltValueField(wireName: r'effectivePrice')
  num? get effectivePrice;

  @BuiltValueField(wireName: r'effectiveDurationMinutes')
  int? get effectiveDurationMinutes;

  @BuiltValueField(wireName: r'isActive')
  bool? get isActive;

  @BuiltValueField(wireName: r'priceType')
  MasterServiceResponsePriceTypeEnum? get priceType;
  // enum priceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'priceMin')
  num? get priceMin;

  @BuiltValueField(wireName: r'priceMax')
  num? get priceMax;

  @BuiltValueField(wireName: r'priceDisplay')
  String? get priceDisplay;

  /// Chosen service type id; null when no service type was selected.
  @BuiltValueField(wireName: r'serviceTypeId')
  String? get serviceTypeId;

  /// Ukrainian display name of the chosen service type; null when none was selected.
  @BuiltValueField(wireName: r'serviceTypeNameUk')
  String? get serviceTypeNameUk;

  MasterServiceResponse._();

  factory MasterServiceResponse(
      [void updates(MasterServiceResponseBuilder b)]) = _$MasterServiceResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MasterServiceResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MasterServiceResponse> get serializer =>
      _$MasterServiceResponseSerializer();
}

class _$MasterServiceResponseSerializer
    implements PrimitiveSerializer<MasterServiceResponse> {
  @override
  final Iterable<Type> types = const [
    MasterServiceResponse,
    _$MasterServiceResponse
  ];

  @override
  final String wireName = r'MasterServiceResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MasterServiceResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
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
    if (object.serviceDefinition != null) {
      yield r'serviceDefinition';
      yield serializers.serialize(
        object.serviceDefinition,
        specifiedType: const FullType(ServiceDefinitionResponse),
      );
    }
    if (object.priceOverride != null) {
      yield r'priceOverride';
      yield serializers.serialize(
        object.priceOverride,
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
    if (object.effectivePrice != null) {
      yield r'effectivePrice';
      yield serializers.serialize(
        object.effectivePrice,
        specifiedType: const FullType(num),
      );
    }
    if (object.effectiveDurationMinutes != null) {
      yield r'effectiveDurationMinutes';
      yield serializers.serialize(
        object.effectiveDurationMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.isActive != null) {
      yield r'isActive';
      yield serializers.serialize(
        object.isActive,
        specifiedType: const FullType(bool),
      );
    }
    if (object.priceType != null) {
      yield r'priceType';
      yield serializers.serialize(
        object.priceType,
        specifiedType: const FullType(MasterServiceResponsePriceTypeEnum),
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
    if (object.priceDisplay != null) {
      yield r'priceDisplay';
      yield serializers.serialize(
        object.priceDisplay,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceTypeId != null) {
      yield r'serviceTypeId';
      yield serializers.serialize(
        object.serviceTypeId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.serviceTypeNameUk != null) {
      yield r'serviceTypeNameUk';
      yield serializers.serialize(
        object.serviceTypeNameUk,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MasterServiceResponse object, {
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
    required MasterServiceResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'serviceDefinition':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ServiceDefinitionResponse),
          ) as ServiceDefinitionResponse;
          result.serviceDefinition.replace(valueDes);
          break;
        case r'priceOverride':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.priceOverride = valueDes;
          break;
        case r'durationOverrideMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationOverrideMinutes = valueDes;
          break;
        case r'effectivePrice':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.effectivePrice = valueDes;
          break;
        case r'effectiveDurationMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.effectiveDurationMinutes = valueDes;
          break;
        case r'isActive':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isActive = valueDes;
          break;
        case r'priceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MasterServiceResponsePriceTypeEnum),
          ) as MasterServiceResponsePriceTypeEnum;
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
            specifiedType: const FullType(num),
          ) as num;
          result.priceMax = valueDes;
          break;
        case r'priceDisplay':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.priceDisplay = valueDes;
          break;
        case r'serviceTypeId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.serviceTypeId = valueDes;
          break;
        case r'serviceTypeNameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.serviceTypeNameUk = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MasterServiceResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MasterServiceResponseBuilder();
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

class MasterServiceResponsePriceTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const MasterServiceResponsePriceTypeEnum FIXED =
      _$masterServiceResponsePriceTypeEnum_FIXED;
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const MasterServiceResponsePriceTypeEnum RANGE =
      _$masterServiceResponsePriceTypeEnum_RANGE;

  static Serializer<MasterServiceResponsePriceTypeEnum> get serializer =>
      _$masterServiceResponsePriceTypeEnumSerializer;

  const MasterServiceResponsePriceTypeEnum._(String name) : super(name);

  static BuiltSet<MasterServiceResponsePriceTypeEnum> get values =>
      _$masterServiceResponsePriceTypeEnumValues;
  static MasterServiceResponsePriceTypeEnum valueOf(String name) =>
      _$masterServiceResponsePriceTypeEnumValueOf(name);
}
