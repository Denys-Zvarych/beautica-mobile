//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/service_price_shape_mismatch_response_salon_price_max.dart';
import 'package:beautica_api/src/model/service_price_shape_mismatch_response_salon_price_min.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'service_price_shape_mismatch_response.g.dart';

/// Payload under `data` of the 400 SERVICE_PRICE_SHAPE_MISMATCH response. Branch on `code`; the remaining fields describe the salon definition's governing price shape.
///
/// Properties:
/// * [code] - Stable machine-readable error code. Always present — the only field the client branches on.
/// * [serviceName] - Display name of the service whose shape clashed (the service type's Ukrainian name).
/// * [existingServiceDefId] - Id of the salon definition that governs the shape, for a deep-link.
/// * [salonPriceType] - The salon definition's pricing mode — the shape the submitted item had to match.
/// * [salonPriceMin]
/// * [salonPriceMax]
@BuiltValue()
abstract class ServicePriceShapeMismatchResponse
    implements
        Built<ServicePriceShapeMismatchResponse,
            ServicePriceShapeMismatchResponseBuilder> {
  /// Stable machine-readable error code. Always present — the only field the client branches on.
  @BuiltValueField(wireName: r'code')
  String? get code;

  /// Display name of the service whose shape clashed (the service type's Ukrainian name).
  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  /// Id of the salon definition that governs the shape, for a deep-link.
  @BuiltValueField(wireName: r'existingServiceDefId')
  String? get existingServiceDefId;

  /// The salon definition's pricing mode — the shape the submitted item had to match.
  @BuiltValueField(wireName: r'salonPriceType')
  ServicePriceShapeMismatchResponseSalonPriceTypeEnum? get salonPriceType;
  // enum salonPriceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'salonPriceMin')
  ServicePriceShapeMismatchResponseSalonPriceMin? get salonPriceMin;

  @BuiltValueField(wireName: r'salonPriceMax')
  ServicePriceShapeMismatchResponseSalonPriceMax? get salonPriceMax;

  ServicePriceShapeMismatchResponse._();

  factory ServicePriceShapeMismatchResponse(
          [void updates(ServicePriceShapeMismatchResponseBuilder b)]) =
      _$ServicePriceShapeMismatchResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServicePriceShapeMismatchResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServicePriceShapeMismatchResponse> get serializer =>
      _$ServicePriceShapeMismatchResponseSerializer();
}

class _$ServicePriceShapeMismatchResponseSerializer
    implements PrimitiveSerializer<ServicePriceShapeMismatchResponse> {
  @override
  final Iterable<Type> types = const [
    ServicePriceShapeMismatchResponse,
    _$ServicePriceShapeMismatchResponse
  ];

  @override
  final String wireName = r'ServicePriceShapeMismatchResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServicePriceShapeMismatchResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.existingServiceDefId != null) {
      yield r'existingServiceDefId';
      yield serializers.serialize(
        object.existingServiceDefId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.salonPriceType != null) {
      yield r'salonPriceType';
      yield serializers.serialize(
        object.salonPriceType,
        specifiedType:
            const FullType(ServicePriceShapeMismatchResponseSalonPriceTypeEnum),
      );
    }
    if (object.salonPriceMin != null) {
      yield r'salonPriceMin';
      yield serializers.serialize(
        object.salonPriceMin,
        specifiedType: const FullType.nullable(
            ServicePriceShapeMismatchResponseSalonPriceMin),
      );
    }
    if (object.salonPriceMax != null) {
      yield r'salonPriceMax';
      yield serializers.serialize(
        object.salonPriceMax,
        specifiedType: const FullType.nullable(
            ServicePriceShapeMismatchResponseSalonPriceMax),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServicePriceShapeMismatchResponse object, {
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
    required ServicePriceShapeMismatchResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.serviceName = valueDes;
          break;
        case r'existingServiceDefId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.existingServiceDefId = valueDes;
          break;
        case r'salonPriceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(
                ServicePriceShapeMismatchResponseSalonPriceTypeEnum),
          ) as ServicePriceShapeMismatchResponseSalonPriceTypeEnum;
          result.salonPriceType = valueDes;
          break;
        case r'salonPriceMin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(
                ServicePriceShapeMismatchResponseSalonPriceMin),
          ) as ServicePriceShapeMismatchResponseSalonPriceMin?;
          if (valueDes == null) continue;
          result.salonPriceMin.replace(valueDes);
          break;
        case r'salonPriceMax':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(
                ServicePriceShapeMismatchResponseSalonPriceMax),
          ) as ServicePriceShapeMismatchResponseSalonPriceMax?;
          if (valueDes == null) continue;
          result.salonPriceMax.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServicePriceShapeMismatchResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServicePriceShapeMismatchResponseBuilder();
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

class ServicePriceShapeMismatchResponseSalonPriceTypeEnum extends EnumClass {
  /// The salon definition's pricing mode — the shape the submitted item had to match.
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const ServicePriceShapeMismatchResponseSalonPriceTypeEnum FIXED =
      _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_FIXED;

  /// The salon definition's pricing mode — the shape the submitted item had to match.
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const ServicePriceShapeMismatchResponseSalonPriceTypeEnum RANGE =
      _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_RANGE;

  static Serializer<ServicePriceShapeMismatchResponseSalonPriceTypeEnum>
      get serializer =>
          _$servicePriceShapeMismatchResponseSalonPriceTypeEnumSerializer;

  const ServicePriceShapeMismatchResponseSalonPriceTypeEnum._(String name)
      : super(name);

  static BuiltSet<ServicePriceShapeMismatchResponseSalonPriceTypeEnum>
      get values => _$servicePriceShapeMismatchResponseSalonPriceTypeEnumValues;
  static ServicePriceShapeMismatchResponseSalonPriceTypeEnum valueOf(
          String name) =>
      _$servicePriceShapeMismatchResponseSalonPriceTypeEnumValueOf(name);
}
