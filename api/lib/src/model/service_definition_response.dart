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
/// * [basePrice]
/// * [bufferMinutesAfter]
/// * [isActive]
/// * [serviceTypeId]
/// * [serviceTypeNameUk]
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
  ServiceDefinitionResponseCategoryEnum? get category;
  // enum categoryEnum {  MANICURE,  PEDICURE,  EYELASH,  HAIRCUT,  MAKEUP,  BROWS,  OTHER,  };

  @BuiltValueField(wireName: r'baseDurationMinutes')
  int? get baseDurationMinutes;

  @BuiltValueField(wireName: r'basePrice')
  num? get basePrice;

  @BuiltValueField(wireName: r'bufferMinutesAfter')
  int? get bufferMinutesAfter;

  @BuiltValueField(wireName: r'isActive')
  bool? get isActive;

  @BuiltValueField(wireName: r'serviceTypeId')
  String? get serviceTypeId;

  @BuiltValueField(wireName: r'serviceTypeNameUk')
  String? get serviceTypeNameUk;

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
        specifiedType: const FullType(ServiceDefinitionResponseCategoryEnum),
      );
    }
    if (object.baseDurationMinutes != null) {
      yield r'baseDurationMinutes';
      yield serializers.serialize(
        object.baseDurationMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.basePrice != null) {
      yield r'basePrice';
      yield serializers.serialize(
        object.basePrice,
        specifiedType: const FullType(num),
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
            specifiedType:
                const FullType(ServiceDefinitionResponseCategoryEnum),
          ) as ServiceDefinitionResponseCategoryEnum;
          result.category = valueDes;
          break;
        case r'baseDurationMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.baseDurationMinutes = valueDes;
          break;
        case r'basePrice':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.basePrice = valueDes;
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

class ServiceDefinitionResponseCategoryEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'MANICURE')
  static const ServiceDefinitionResponseCategoryEnum MANICURE =
      _$serviceDefinitionResponseCategoryEnum_MANICURE;
  @BuiltValueEnumConst(wireName: r'PEDICURE')
  static const ServiceDefinitionResponseCategoryEnum PEDICURE =
      _$serviceDefinitionResponseCategoryEnum_PEDICURE;
  @BuiltValueEnumConst(wireName: r'EYELASH')
  static const ServiceDefinitionResponseCategoryEnum EYELASH =
      _$serviceDefinitionResponseCategoryEnum_EYELASH;
  @BuiltValueEnumConst(wireName: r'HAIRCUT')
  static const ServiceDefinitionResponseCategoryEnum HAIRCUT =
      _$serviceDefinitionResponseCategoryEnum_HAIRCUT;
  @BuiltValueEnumConst(wireName: r'MAKEUP')
  static const ServiceDefinitionResponseCategoryEnum MAKEUP =
      _$serviceDefinitionResponseCategoryEnum_MAKEUP;
  @BuiltValueEnumConst(wireName: r'BROWS')
  static const ServiceDefinitionResponseCategoryEnum BROWS =
      _$serviceDefinitionResponseCategoryEnum_BROWS;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const ServiceDefinitionResponseCategoryEnum OTHER =
      _$serviceDefinitionResponseCategoryEnum_OTHER;

  static Serializer<ServiceDefinitionResponseCategoryEnum> get serializer =>
      _$serviceDefinitionResponseCategoryEnumSerializer;

  const ServiceDefinitionResponseCategoryEnum._(String name) : super(name);

  static BuiltSet<ServiceDefinitionResponseCategoryEnum> get values =>
      _$serviceDefinitionResponseCategoryEnumValues;
  static ServiceDefinitionResponseCategoryEnum valueOf(String name) =>
      _$serviceDefinitionResponseCategoryEnumValueOf(name);
}
