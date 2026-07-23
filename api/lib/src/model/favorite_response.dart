//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'favorite_response.g.dart';

/// FavoriteResponse
///
/// Properties:
/// * [id]
/// * [targetType]
/// * [targetId]
/// * [createdAt]
@BuiltValue()
abstract class FavoriteResponse
    implements Built<FavoriteResponse, FavoriteResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'targetType')
  FavoriteResponseTargetTypeEnum? get targetType;
  // enum targetTypeEnum {  MASTER,  SALON,  };

  @BuiltValueField(wireName: r'targetId')
  String? get targetId;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  FavoriteResponse._();

  factory FavoriteResponse([void updates(FavoriteResponseBuilder b)]) =
      _$FavoriteResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FavoriteResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FavoriteResponse> get serializer =>
      _$FavoriteResponseSerializer();
}

class _$FavoriteResponseSerializer
    implements PrimitiveSerializer<FavoriteResponse> {
  @override
  final Iterable<Type> types = const [FavoriteResponse, _$FavoriteResponse];

  @override
  final String wireName = r'FavoriteResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FavoriteResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.targetType != null) {
      yield r'targetType';
      yield serializers.serialize(
        object.targetType,
        specifiedType: const FullType(FavoriteResponseTargetTypeEnum),
      );
    }
    if (object.targetId != null) {
      yield r'targetId';
      yield serializers.serialize(
        object.targetId,
        specifiedType: const FullType(String),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FavoriteResponse object, {
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
    required FavoriteResponseBuilder result,
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
        case r'targetType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(FavoriteResponseTargetTypeEnum),
          ) as FavoriteResponseTargetTypeEnum;
          result.targetType = valueDes;
          break;
        case r'targetId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetId = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FavoriteResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FavoriteResponseBuilder();
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

class FavoriteResponseTargetTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'MASTER')
  static const FavoriteResponseTargetTypeEnum MASTER =
      _$favoriteResponseTargetTypeEnum_MASTER;
  @BuiltValueEnumConst(wireName: r'SALON')
  static const FavoriteResponseTargetTypeEnum SALON =
      _$favoriteResponseTargetTypeEnum_SALON;

  static Serializer<FavoriteResponseTargetTypeEnum> get serializer =>
      _$favoriteResponseTargetTypeEnumSerializer;

  const FavoriteResponseTargetTypeEnum._(String name) : super(name);

  static BuiltSet<FavoriteResponseTargetTypeEnum> get values =>
      _$favoriteResponseTargetTypeEnumValues;
  static FavoriteResponseTargetTypeEnum valueOf(String name) =>
      _$favoriteResponseTargetTypeEnumValueOf(name);
}
