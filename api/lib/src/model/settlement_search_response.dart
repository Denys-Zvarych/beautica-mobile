//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'settlement_search_response.g.dart';

/// SettlementSearchResponse
///
/// Properties:
/// * [settlementId]
/// * [nameUk]
/// * [settlementType]
/// * [oblastNameUk]
/// * [hromadaNameUk]
@BuiltValue()
abstract class SettlementSearchResponse
    implements
        Built<SettlementSearchResponse, SettlementSearchResponseBuilder> {
  @BuiltValueField(wireName: r'settlementId')
  String? get settlementId;

  @BuiltValueField(wireName: r'nameUk')
  String? get nameUk;

  @BuiltValueField(wireName: r'settlementType')
  SettlementSearchResponseSettlementTypeEnum? get settlementType;
  // enum settlementTypeEnum {  CITY,  TOWN,  VILLAGE,  SETTLEMENT,  };

  @BuiltValueField(wireName: r'oblastNameUk')
  String? get oblastNameUk;

  @BuiltValueField(wireName: r'hromadaNameUk')
  String? get hromadaNameUk;

  SettlementSearchResponse._();

  factory SettlementSearchResponse(
          [void updates(SettlementSearchResponseBuilder b)]) =
      _$SettlementSearchResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SettlementSearchResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SettlementSearchResponse> get serializer =>
      _$SettlementSearchResponseSerializer();
}

class _$SettlementSearchResponseSerializer
    implements PrimitiveSerializer<SettlementSearchResponse> {
  @override
  final Iterable<Type> types = const [
    SettlementSearchResponse,
    _$SettlementSearchResponse
  ];

  @override
  final String wireName = r'SettlementSearchResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SettlementSearchResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.settlementId != null) {
      yield r'settlementId';
      yield serializers.serialize(
        object.settlementId,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameUk != null) {
      yield r'nameUk';
      yield serializers.serialize(
        object.nameUk,
        specifiedType: const FullType(String),
      );
    }
    if (object.settlementType != null) {
      yield r'settlementType';
      yield serializers.serialize(
        object.settlementType,
        specifiedType:
            const FullType(SettlementSearchResponseSettlementTypeEnum),
      );
    }
    if (object.oblastNameUk != null) {
      yield r'oblastNameUk';
      yield serializers.serialize(
        object.oblastNameUk,
        specifiedType: const FullType(String),
      );
    }
    if (object.hromadaNameUk != null) {
      yield r'hromadaNameUk';
      yield serializers.serialize(
        object.hromadaNameUk,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SettlementSearchResponse object, {
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
    required SettlementSearchResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'settlementId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.settlementId = valueDes;
          break;
        case r'nameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameUk = valueDes;
          break;
        case r'settlementType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(SettlementSearchResponseSettlementTypeEnum),
          ) as SettlementSearchResponseSettlementTypeEnum;
          result.settlementType = valueDes;
          break;
        case r'oblastNameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.oblastNameUk = valueDes;
          break;
        case r'hromadaNameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.hromadaNameUk = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SettlementSearchResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SettlementSearchResponseBuilder();
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

class SettlementSearchResponseSettlementTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CITY')
  static const SettlementSearchResponseSettlementTypeEnum CITY =
      _$settlementSearchResponseSettlementTypeEnum_CITY;
  @BuiltValueEnumConst(wireName: r'TOWN')
  static const SettlementSearchResponseSettlementTypeEnum TOWN =
      _$settlementSearchResponseSettlementTypeEnum_TOWN;
  @BuiltValueEnumConst(wireName: r'VILLAGE')
  static const SettlementSearchResponseSettlementTypeEnum VILLAGE =
      _$settlementSearchResponseSettlementTypeEnum_VILLAGE;
  @BuiltValueEnumConst(wireName: r'SETTLEMENT')
  static const SettlementSearchResponseSettlementTypeEnum SETTLEMENT =
      _$settlementSearchResponseSettlementTypeEnum_SETTLEMENT;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const SettlementSearchResponseSettlementTypeEnum
      unknownDefaultOpenApi =
      _$settlementSearchResponseSettlementTypeEnum_unknownDefaultOpenApi;

  static Serializer<SettlementSearchResponseSettlementTypeEnum>
      get serializer => _$settlementSearchResponseSettlementTypeEnumSerializer;

  const SettlementSearchResponseSettlementTypeEnum._(String name) : super(name);

  static BuiltSet<SettlementSearchResponseSettlementTypeEnum> get values =>
      _$settlementSearchResponseSettlementTypeEnumValues;
  static SettlementSearchResponseSettlementTypeEnum valueOf(String name) =>
      _$settlementSearchResponseSettlementTypeEnumValueOf(name);
}
