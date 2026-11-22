//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item.g.dart';

/// Item
///
/// Properties:
/// * [bookingId]
/// * [serviceName]
/// * [status]
/// * [startsAt]
/// * [masterId]
/// * [masterDisplayName]
/// * [priceAtBooking]
/// * [priceMaxAtBooking]
@BuiltValue()
abstract class Item implements Built<Item, ItemBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'status')
  ItemStatusEnum? get status;
  // enum statusEnum {  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'masterDisplayName')
  String? get masterDisplayName;

  @BuiltValueField(wireName: r'priceAtBooking')
  num? get priceAtBooking;

  @BuiltValueField(wireName: r'priceMaxAtBooking')
  num? get priceMaxAtBooking;

  Item._();

  factory Item([void updates(ItemBuilder b)]) = _$Item;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Item> get serializer => _$ItemSerializer();
}

class _$ItemSerializer implements PrimitiveSerializer<Item> {
  @override
  final Iterable<Type> types = const [Item, _$Item];

  @override
  final String wireName = r'Item';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Item object, {
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
    if (object.status != null) {
      yield r'status';
      yield serializers.serialize(
        object.status,
        specifiedType: const FullType(ItemStatusEnum),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterDisplayName != null) {
      yield r'masterDisplayName';
      yield serializers.serialize(
        object.masterDisplayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.priceAtBooking != null) {
      yield r'priceAtBooking';
      yield serializers.serialize(
        object.priceAtBooking,
        specifiedType: const FullType(num),
      );
    }
    if (object.priceMaxAtBooking != null) {
      yield r'priceMaxAtBooking';
      yield serializers.serialize(
        object.priceMaxAtBooking,
        specifiedType: const FullType(num),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Item object, {
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
    required ItemBuilder result,
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
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ItemStatusEnum),
          ) as ItemStatusEnum;
          result.status = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'masterDisplayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterDisplayName = valueDes;
          break;
        case r'priceAtBooking':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.priceAtBooking = valueDes;
          break;
        case r'priceMaxAtBooking':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.priceMaxAtBooking = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Item deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemBuilder();
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

class ItemStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const ItemStatusEnum CONFIRMED = _$itemStatusEnum_CONFIRMED;
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const ItemStatusEnum DECLINED = _$itemStatusEnum_DECLINED;
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const ItemStatusEnum COMPLETED = _$itemStatusEnum_COMPLETED;
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const ItemStatusEnum NOT_COMPLETED = _$itemStatusEnum_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const ItemStatusEnum CANCELLED = _$itemStatusEnum_CANCELLED;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ItemStatusEnum unknownDefaultOpenApi =
      _$itemStatusEnum_unknownDefaultOpenApi;

  static Serializer<ItemStatusEnum> get serializer =>
      _$itemStatusEnumSerializer;

  const ItemStatusEnum._(String name) : super(name);

  static BuiltSet<ItemStatusEnum> get values => _$itemStatusEnumValues;
  static ItemStatusEnum valueOf(String name) => _$itemStatusEnumValueOf(name);
}
