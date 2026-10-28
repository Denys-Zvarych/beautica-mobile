//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'block_response.g.dart';

/// BlockResponse
///
/// Properties:
/// * [id]
/// * [kind]
/// * [displayName]
/// * [avatarUrl] - Live avatar of the blocked account. CLIENT rows only; null for GUEST.
/// * [maskedPhone] - Masked guest phone, last four digits only. GUEST rows only; null for CLIENT.
/// * [createdAt]
@BuiltValue()
abstract class BlockResponse
    implements Built<BlockResponse, BlockResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'kind')
  BlockResponseKindEnum? get kind;
  // enum kindEnum {  CLIENT,  GUEST,  };

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  /// Live avatar of the blocked account. CLIENT rows only; null for GUEST.
  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  /// Masked guest phone, last four digits only. GUEST rows only; null for CLIENT.
  @BuiltValueField(wireName: r'maskedPhone')
  String? get maskedPhone;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  BlockResponse._();

  factory BlockResponse([void updates(BlockResponseBuilder b)]) =
      _$BlockResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BlockResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BlockResponse> get serializer =>
      _$BlockResponseSerializer();
}

class _$BlockResponseSerializer implements PrimitiveSerializer<BlockResponse> {
  @override
  final Iterable<Type> types = const [BlockResponse, _$BlockResponse];

  @override
  final String wireName = r'BlockResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BlockResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType(BlockResponseKindEnum),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.maskedPhone != null) {
      yield r'maskedPhone';
      yield serializers.serialize(
        object.maskedPhone,
        specifiedType: const FullType.nullable(String),
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
    BlockResponse object, {
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
    required BlockResponseBuilder result,
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
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BlockResponseKindEnum),
          ) as BlockResponseKindEnum;
          result.kind = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.avatarUrl = valueDes;
          break;
        case r'maskedPhone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.maskedPhone = valueDes;
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
  BlockResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BlockResponseBuilder();
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

class BlockResponseKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const BlockResponseKindEnum CLIENT = _$blockResponseKindEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'GUEST')
  static const BlockResponseKindEnum GUEST = _$blockResponseKindEnum_GUEST;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const BlockResponseKindEnum unknownDefaultOpenApi =
      _$blockResponseKindEnum_unknownDefaultOpenApi;

  static Serializer<BlockResponseKindEnum> get serializer =>
      _$blockResponseKindEnumSerializer;

  const BlockResponseKindEnum._(String name) : super(name);

  static BuiltSet<BlockResponseKindEnum> get values =>
      _$blockResponseKindEnumValues;
  static BlockResponseKindEnum valueOf(String name) =>
      _$blockResponseKindEnumValueOf(name);
}
