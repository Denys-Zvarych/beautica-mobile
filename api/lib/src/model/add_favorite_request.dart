//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_favorite_request.g.dart';

/// AddFavoriteRequest
///
/// Properties:
/// * [targetType]
/// * [targetId]
@BuiltValue()
abstract class AddFavoriteRequest
    implements Built<AddFavoriteRequest, AddFavoriteRequestBuilder> {
  @BuiltValueField(wireName: r'targetType')
  AddFavoriteRequestTargetTypeEnum get targetType;
  // enum targetTypeEnum {  MASTER,  SALON,  SERVICE,  SALON_SERVICE,  };

  @BuiltValueField(wireName: r'targetId')
  String get targetId;

  AddFavoriteRequest._();

  factory AddFavoriteRequest([void updates(AddFavoriteRequestBuilder b)]) =
      _$AddFavoriteRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddFavoriteRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddFavoriteRequest> get serializer =>
      _$AddFavoriteRequestSerializer();
}

class _$AddFavoriteRequestSerializer
    implements PrimitiveSerializer<AddFavoriteRequest> {
  @override
  final Iterable<Type> types = const [AddFavoriteRequest, _$AddFavoriteRequest];

  @override
  final String wireName = r'AddFavoriteRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddFavoriteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'targetType';
    yield serializers.serialize(
      object.targetType,
      specifiedType: const FullType(AddFavoriteRequestTargetTypeEnum),
    );
    yield r'targetId';
    yield serializers.serialize(
      object.targetId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AddFavoriteRequest object, {
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
    required AddFavoriteRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'targetType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AddFavoriteRequestTargetTypeEnum),
          ) as AddFavoriteRequestTargetTypeEnum;
          result.targetType = valueDes;
          break;
        case r'targetId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AddFavoriteRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddFavoriteRequestBuilder();
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

class AddFavoriteRequestTargetTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'MASTER')
  static const AddFavoriteRequestTargetTypeEnum MASTER =
      _$addFavoriteRequestTargetTypeEnum_MASTER;
  @BuiltValueEnumConst(wireName: r'SALON')
  static const AddFavoriteRequestTargetTypeEnum SALON =
      _$addFavoriteRequestTargetTypeEnum_SALON;
  @BuiltValueEnumConst(wireName: r'SERVICE')
  static const AddFavoriteRequestTargetTypeEnum SERVICE =
      _$addFavoriteRequestTargetTypeEnum_SERVICE;
  @BuiltValueEnumConst(wireName: r'SALON_SERVICE')
  static const AddFavoriteRequestTargetTypeEnum SALON_SERVICE =
      _$addFavoriteRequestTargetTypeEnum_SALON_SERVICE;

  static Serializer<AddFavoriteRequestTargetTypeEnum> get serializer =>
      _$addFavoriteRequestTargetTypeEnumSerializer;

  const AddFavoriteRequestTargetTypeEnum._(String name) : super(name);

  static BuiltSet<AddFavoriteRequestTargetTypeEnum> get values =>
      _$addFavoriteRequestTargetTypeEnumValues;
  static AddFavoriteRequestTargetTypeEnum valueOf(String name) =>
      _$addFavoriteRequestTargetTypeEnumValueOf(name);
}
