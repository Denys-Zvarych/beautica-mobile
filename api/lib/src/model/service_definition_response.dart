//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'service_definition_response.g.dart';

/// ServiceDefinitionResponse
///
/// Properties:
/// * [id]
/// * [name]
/// * [description]
/// * [category]
/// * [baseDurationMinutes]
/// * [bufferMinutesAfter]
/// * [isActive]
/// * [serviceTypeId]
/// * [serviceTypeNameUk]
/// * [photoUrl]
/// * [priceType]
/// * [priceMin]
/// * [priceMax]
/// * [priceDisplay]
@BuiltValue()
abstract class ServiceDefinitionResponse
    implements
        Built<ServiceDefinitionResponse, ServiceDefinitionResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

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

  @BuiltValueField(wireName: r'isActive')
  bool? get isActive;

  @BuiltValueField(wireName: r'serviceTypeId')
  String? get serviceTypeId;

  @BuiltValueField(wireName: r'serviceTypeNameUk')
  String? get serviceTypeNameUk;

  @BuiltValueField(wireName: r'photoUrl')
  String? get photoUrl;

  @BuiltValueField(wireName: r'priceType')
  ServiceDefinitionResponsePriceTypeEnum? get priceType;
  // enum priceTypeEnum {  FIXED,  RANGE,  };

  @BuiltValueField(wireName: r'priceMin')
  num? get priceMin;

  @BuiltValueField(wireName: r'priceMax')
  num? get priceMax;

  @BuiltValueField(wireName: r'priceDisplay')
  String? get priceDisplay;

  ServiceDefinitionResponse._();

  factory ServiceDefinitionResponse(
          [void updates(ServiceDefinitionResponseBuilder b)]) =
      _$ServiceDefinitionResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServiceDefinitionResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServiceDefinitionResponse> get serializer =>
      _$ServiceDefinitionResponseSerializer();
}

class _$ServiceDefinitionResponseSerializer
    implements PrimitiveSerializer<ServiceDefinitionResponse> {
  @override
  final Iterable<Type> types = const [
    ServiceDefinitionResponse,
    _$ServiceDefinitionResponse
  ];

  @override
  final String wireName = r'ServiceDefinitionResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServiceDefinitionResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
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
    if (object.isActive != null) {
      yield r'isActive';
      yield serializers.serialize(
        object.isActive,
        specifiedType: const FullType(bool),
      );
    }
    if (object.serviceTypeId != null) {
      yield r'serviceTypeId';
      yield serializers.serialize(
        object.serviceTypeId,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceTypeNameUk != null) {
      yield r'serviceTypeNameUk';
      yield serializers.serialize(
        object.serviceTypeNameUk,
        specifiedType: const FullType(String),
      );
    }
    if (object.photoUrl != null) {
      yield r'photoUrl';
      yield serializers.serialize(
        object.photoUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.priceType != null) {
      yield r'priceType';
      yield serializers.serialize(
        object.priceType,
        specifiedType: const FullType(ServiceDefinitionResponsePriceTypeEnum),
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
  }

  @override
  Object serialize(
    Serializers serializers,
    ServiceDefinitionResponse object, {
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
    required ServiceDefinitionResponseBuilder result,
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
        case r'isActive':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isActive = valueDes;
          break;
        case r'serviceTypeId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceTypeId = valueDes;
          break;
        case r'serviceTypeNameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceTypeNameUk = valueDes;
          break;
        case r'photoUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.photoUrl = valueDes;
          break;
        case r'priceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(ServiceDefinitionResponsePriceTypeEnum),
          ) as ServiceDefinitionResponsePriceTypeEnum;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServiceDefinitionResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServiceDefinitionResponseBuilder();
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

class ServiceDefinitionResponsePriceTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'FIXED')
  static const ServiceDefinitionResponsePriceTypeEnum FIXED =
      _$serviceDefinitionResponsePriceTypeEnum_FIXED;
  @BuiltValueEnumConst(wireName: r'RANGE')
  static const ServiceDefinitionResponsePriceTypeEnum RANGE =
      _$serviceDefinitionResponsePriceTypeEnum_RANGE;

  static Serializer<ServiceDefinitionResponsePriceTypeEnum> get serializer =>
      _$serviceDefinitionResponsePriceTypeEnumSerializer;

  const ServiceDefinitionResponsePriceTypeEnum._(String name) : super(name);

  static BuiltSet<ServiceDefinitionResponsePriceTypeEnum> get values =>
      _$serviceDefinitionResponsePriceTypeEnumValues;
  static ServiceDefinitionResponsePriceTypeEnum valueOf(String name) =>
      _$serviceDefinitionResponsePriceTypeEnumValueOf(name);
}
