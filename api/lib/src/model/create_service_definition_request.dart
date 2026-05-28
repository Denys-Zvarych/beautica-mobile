//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_service_definition_request.g.dart';

/// CreateServiceDefinitionRequest
///
/// Properties:
/// * [name]
/// * [description]
/// * [category]
/// * [baseDurationMinutes]
/// * [basePrice]
/// * [bufferMinutesAfter]
/// * [serviceTypeId]
@BuiltValue()
abstract class CreateServiceDefinitionRequest
    implements
        Built<CreateServiceDefinitionRequest,
            CreateServiceDefinitionRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'description')
  String? get description;

  @BuiltValueField(wireName: r'category')
  CreateServiceDefinitionRequestCategoryEnum? get category;
  // enum categoryEnum {  MANICURE,  PEDICURE,  EYELASH,  HAIRCUT,  MAKEUP,  BROWS,  OTHER,  };

  @BuiltValueField(wireName: r'baseDurationMinutes')
  int get baseDurationMinutes;

  @BuiltValueField(wireName: r'basePrice')
  num get basePrice;

  @BuiltValueField(wireName: r'bufferMinutesAfter')
  int? get bufferMinutesAfter;

  @BuiltValueField(wireName: r'serviceTypeId')
  String? get serviceTypeId;

  CreateServiceDefinitionRequest._();

  factory CreateServiceDefinitionRequest(
          [void updates(CreateServiceDefinitionRequestBuilder b)]) =
      _$CreateServiceDefinitionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateServiceDefinitionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateServiceDefinitionRequest> get serializer =>
      _$CreateServiceDefinitionRequestSerializer();
}

class _$CreateServiceDefinitionRequestSerializer
    implements PrimitiveSerializer<CreateServiceDefinitionRequest> {
  @override
  final Iterable<Type> types = const [
    CreateServiceDefinitionRequest,
    _$CreateServiceDefinitionRequest
  ];

  @override
  final String wireName = r'CreateServiceDefinitionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateServiceDefinitionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
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
        specifiedType:
            const FullType(CreateServiceDefinitionRequestCategoryEnum),
      );
    }
    yield r'baseDurationMinutes';
    yield serializers.serialize(
      object.baseDurationMinutes,
      specifiedType: const FullType(int),
    );
    yield r'basePrice';
    yield serializers.serialize(
      object.basePrice,
      specifiedType: const FullType(num),
    );
    if (object.bufferMinutesAfter != null) {
      yield r'bufferMinutesAfter';
      yield serializers.serialize(
        object.bufferMinutesAfter,
        specifiedType: const FullType(int),
      );
    }
    if (object.serviceTypeId != null) {
      yield r'serviceTypeId';
      yield serializers.serialize(
        object.serviceTypeId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateServiceDefinitionRequest object, {
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
    required CreateServiceDefinitionRequestBuilder result,
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
            specifiedType:
                const FullType(CreateServiceDefinitionRequestCategoryEnum),
          ) as CreateServiceDefinitionRequestCategoryEnum;
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
        case r'serviceTypeId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
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
  CreateServiceDefinitionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateServiceDefinitionRequestBuilder();
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

class CreateServiceDefinitionRequestCategoryEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'MANICURE')
  static const CreateServiceDefinitionRequestCategoryEnum MANICURE =
      _$createServiceDefinitionRequestCategoryEnum_MANICURE;
  @BuiltValueEnumConst(wireName: r'PEDICURE')
  static const CreateServiceDefinitionRequestCategoryEnum PEDICURE =
      _$createServiceDefinitionRequestCategoryEnum_PEDICURE;
  @BuiltValueEnumConst(wireName: r'EYELASH')
  static const CreateServiceDefinitionRequestCategoryEnum EYELASH =
      _$createServiceDefinitionRequestCategoryEnum_EYELASH;
  @BuiltValueEnumConst(wireName: r'HAIRCUT')
  static const CreateServiceDefinitionRequestCategoryEnum HAIRCUT =
      _$createServiceDefinitionRequestCategoryEnum_HAIRCUT;
  @BuiltValueEnumConst(wireName: r'MAKEUP')
  static const CreateServiceDefinitionRequestCategoryEnum MAKEUP =
      _$createServiceDefinitionRequestCategoryEnum_MAKEUP;
  @BuiltValueEnumConst(wireName: r'BROWS')
  static const CreateServiceDefinitionRequestCategoryEnum BROWS =
      _$createServiceDefinitionRequestCategoryEnum_BROWS;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const CreateServiceDefinitionRequestCategoryEnum OTHER =
      _$createServiceDefinitionRequestCategoryEnum_OTHER;

  static Serializer<CreateServiceDefinitionRequestCategoryEnum>
      get serializer => _$createServiceDefinitionRequestCategoryEnumSerializer;

  const CreateServiceDefinitionRequestCategoryEnum._(String name) : super(name);

  static BuiltSet<CreateServiceDefinitionRequestCategoryEnum> get values =>
      _$createServiceDefinitionRequestCategoryEnumValues;
  static CreateServiceDefinitionRequestCategoryEnum valueOf(String name) =>
      _$createServiceDefinitionRequestCategoryEnumValueOf(name);
}
