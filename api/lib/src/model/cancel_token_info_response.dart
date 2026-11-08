//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/cancel_token_item_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cancel_token_info_response.g.dart';

/// CancelTokenInfoResponse
///
/// Properties:
/// * [masterName]
/// * [serviceName]
/// * [startsAt]
/// * [cancellable]
/// * [windowClosesAt]
/// * [status]
/// * [rebookPath]
/// * [salonName]
/// * [address]
/// * [locationNote]
/// * [items]
@BuiltValue()
abstract class CancelTokenInfoResponse
    implements Built<CancelTokenInfoResponse, CancelTokenInfoResponseBuilder> {
  @BuiltValueField(wireName: r'masterName')
  String? get masterName;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'cancellable')
  bool? get cancellable;

  @BuiltValueField(wireName: r'windowClosesAt')
  DateTime? get windowClosesAt;

  @BuiltValueField(wireName: r'status')
  CancelTokenInfoResponseStatusEnum? get status;
  // enum statusEnum {  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'rebookPath')
  String? get rebookPath;

  @BuiltValueField(wireName: r'salonName')
  String? get salonName;

  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  @BuiltValueField(wireName: r'items')
  BuiltList<CancelTokenItemResponse>? get items;

  CancelTokenInfoResponse._();

  factory CancelTokenInfoResponse(
          [void updates(CancelTokenInfoResponseBuilder b)]) =
      _$CancelTokenInfoResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CancelTokenInfoResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CancelTokenInfoResponse> get serializer =>
      _$CancelTokenInfoResponseSerializer();
}

class _$CancelTokenInfoResponseSerializer
    implements PrimitiveSerializer<CancelTokenInfoResponse> {
  @override
  final Iterable<Type> types = const [
    CancelTokenInfoResponse,
    _$CancelTokenInfoResponse
  ];

  @override
  final String wireName = r'CancelTokenInfoResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CancelTokenInfoResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterName != null) {
      yield r'masterName';
      yield serializers.serialize(
        object.masterName,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.cancellable != null) {
      yield r'cancellable';
      yield serializers.serialize(
        object.cancellable,
        specifiedType: const FullType(bool),
      );
    }
    if (object.windowClosesAt != null) {
      yield r'windowClosesAt';
      yield serializers.serialize(
        object.windowClosesAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.status != null) {
      yield r'status';
      yield serializers.serialize(
        object.status,
        specifiedType: const FullType(CancelTokenInfoResponseStatusEnum),
      );
    }
    if (object.rebookPath != null) {
      yield r'rebookPath';
      yield serializers.serialize(
        object.rebookPath,
        specifiedType: const FullType(String),
      );
    }
    if (object.salonName != null) {
      yield r'salonName';
      yield serializers.serialize(
        object.salonName,
        specifiedType: const FullType(String),
      );
    }
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType(String),
      );
    }
    if (object.items != null) {
      yield r'items';
      yield serializers.serialize(
        object.items,
        specifiedType:
            const FullType(BuiltList, [FullType(CancelTokenItemResponse)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CancelTokenInfoResponse object, {
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
    required CancelTokenInfoResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterName = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'cancellable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.cancellable = valueDes;
          break;
        case r'windowClosesAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.windowClosesAt = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CancelTokenInfoResponseStatusEnum),
          ) as CancelTokenInfoResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'rebookPath':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.rebookPath = valueDes;
          break;
        case r'salonName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.salonName = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'locationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.locationNote = valueDes;
          break;
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(CancelTokenItemResponse)]),
          ) as BuiltList<CancelTokenItemResponse>;
          result.items.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CancelTokenInfoResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CancelTokenInfoResponseBuilder();
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

class CancelTokenInfoResponseStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const CancelTokenInfoResponseStatusEnum CONFIRMED =
      _$cancelTokenInfoResponseStatusEnum_CONFIRMED;
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const CancelTokenInfoResponseStatusEnum DECLINED =
      _$cancelTokenInfoResponseStatusEnum_DECLINED;
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const CancelTokenInfoResponseStatusEnum COMPLETED =
      _$cancelTokenInfoResponseStatusEnum_COMPLETED;
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const CancelTokenInfoResponseStatusEnum NOT_COMPLETED =
      _$cancelTokenInfoResponseStatusEnum_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const CancelTokenInfoResponseStatusEnum CANCELLED =
      _$cancelTokenInfoResponseStatusEnum_CANCELLED;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const CancelTokenInfoResponseStatusEnum unknownDefaultOpenApi =
      _$cancelTokenInfoResponseStatusEnum_unknownDefaultOpenApi;

  static Serializer<CancelTokenInfoResponseStatusEnum> get serializer =>
      _$cancelTokenInfoResponseStatusEnumSerializer;

  const CancelTokenInfoResponseStatusEnum._(String name) : super(name);

  static BuiltSet<CancelTokenInfoResponseStatusEnum> get values =>
      _$cancelTokenInfoResponseStatusEnumValues;
  static CancelTokenInfoResponseStatusEnum valueOf(String name) =>
      _$cancelTokenInfoResponseStatusEnumValueOf(name);
}
