//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cancel_token_item_response.g.dart';

/// CancelTokenItemResponse
///
/// Properties:
/// * [bookingId]
/// * [serviceName]
/// * [startsAt]
/// * [durationMinutes]
/// * [status]
/// * [cancellable]
@BuiltValue()
abstract class CancelTokenItemResponse
    implements Built<CancelTokenItemResponse, CancelTokenItemResponseBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'durationMinutes')
  int? get durationMinutes;

  @BuiltValueField(wireName: r'status')
  CancelTokenItemResponseStatusEnum? get status;
  // enum statusEnum {  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'cancellable')
  bool? get cancellable;

  CancelTokenItemResponse._();

  factory CancelTokenItemResponse(
          [void updates(CancelTokenItemResponseBuilder b)]) =
      _$CancelTokenItemResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CancelTokenItemResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CancelTokenItemResponse> get serializer =>
      _$CancelTokenItemResponseSerializer();
}

class _$CancelTokenItemResponseSerializer
    implements PrimitiveSerializer<CancelTokenItemResponse> {
  @override
  final Iterable<Type> types = const [
    CancelTokenItemResponse,
    _$CancelTokenItemResponse
  ];

  @override
  final String wireName = r'CancelTokenItemResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CancelTokenItemResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.bookingId != null) {
      yield r'bookingId';
      yield serializers.serialize(
        object.bookingId,
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
    if (object.durationMinutes != null) {
      yield r'durationMinutes';
      yield serializers.serialize(
        object.durationMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.status != null) {
      yield r'status';
      yield serializers.serialize(
        object.status,
        specifiedType: const FullType(CancelTokenItemResponseStatusEnum),
      );
    }
    if (object.cancellable != null) {
      yield r'cancellable';
      yield serializers.serialize(
        object.cancellable,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CancelTokenItemResponse object, {
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
    required CancelTokenItemResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bookingId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
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
        case r'durationMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMinutes = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CancelTokenItemResponseStatusEnum),
          ) as CancelTokenItemResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'cancellable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.cancellable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CancelTokenItemResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CancelTokenItemResponseBuilder();
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

class CancelTokenItemResponseStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const CancelTokenItemResponseStatusEnum CONFIRMED =
      _$cancelTokenItemResponseStatusEnum_CONFIRMED;
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const CancelTokenItemResponseStatusEnum DECLINED =
      _$cancelTokenItemResponseStatusEnum_DECLINED;
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const CancelTokenItemResponseStatusEnum COMPLETED =
      _$cancelTokenItemResponseStatusEnum_COMPLETED;
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const CancelTokenItemResponseStatusEnum NOT_COMPLETED =
      _$cancelTokenItemResponseStatusEnum_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const CancelTokenItemResponseStatusEnum CANCELLED =
      _$cancelTokenItemResponseStatusEnum_CANCELLED;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const CancelTokenItemResponseStatusEnum unknownDefaultOpenApi =
      _$cancelTokenItemResponseStatusEnum_unknownDefaultOpenApi;

  static Serializer<CancelTokenItemResponseStatusEnum> get serializer =>
      _$cancelTokenItemResponseStatusEnumSerializer;

  const CancelTokenItemResponseStatusEnum._(String name) : super(name);

  static BuiltSet<CancelTokenItemResponseStatusEnum> get values =>
      _$cancelTokenItemResponseStatusEnumValues;
  static CancelTokenItemResponseStatusEnum valueOf(String name) =>
      _$cancelTokenItemResponseStatusEnumValueOf(name);
}
