//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_response.g.dart';

/// BookingResponse
///
/// Properties:
/// * [id]
/// * [clientId]
/// * [masterId]
/// * [masterServiceId]
/// * [serviceName]
/// * [status]
/// * [startsAt]
/// * [endsAt]
/// * [priceAtBooking]
/// * [priceMaxAtBooking] - The range ceiling agreed AT BOOKING TIME, present ONLY when the master left this service's price as a genuine RANGE (no priceOverride) when the booking was made. Null means a single price — render priceAtBooking alone. The client must never re-derive this from priceType/priceOverride; the decision is made server-side, once.
/// * [durationMinutesAtBooking]
/// * [createdAt]
@BuiltValue()
abstract class BookingResponse
    implements Built<BookingResponse, BookingResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'clientId')
  String? get clientId;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'masterServiceId')
  String? get masterServiceId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'status')
  BookingResponseStatusEnum? get status;
  // enum statusEnum {  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'endsAt')
  DateTime? get endsAt;

  @BuiltValueField(wireName: r'priceAtBooking')
  num? get priceAtBooking;

  /// The range ceiling agreed AT BOOKING TIME, present ONLY when the master left this service's price as a genuine RANGE (no priceOverride) when the booking was made. Null means a single price — render priceAtBooking alone. The client must never re-derive this from priceType/priceOverride; the decision is made server-side, once.
  @BuiltValueField(wireName: r'priceMaxAtBooking')
  num? get priceMaxAtBooking;

  @BuiltValueField(wireName: r'durationMinutesAtBooking')
  int? get durationMinutesAtBooking;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  BookingResponse._();

  factory BookingResponse([void updates(BookingResponseBuilder b)]) =
      _$BookingResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingResponse> get serializer =>
      _$BookingResponseSerializer();
}

class _$BookingResponseSerializer
    implements PrimitiveSerializer<BookingResponse> {
  @override
  final Iterable<Type> types = const [BookingResponse, _$BookingResponse];

  @override
  final String wireName = r'BookingResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.clientId != null) {
      yield r'clientId';
      yield serializers.serialize(
        object.clientId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterServiceId != null) {
      yield r'masterServiceId';
      yield serializers.serialize(
        object.masterServiceId,
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
        specifiedType: const FullType(BookingResponseStatusEnum),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.endsAt != null) {
      yield r'endsAt';
      yield serializers.serialize(
        object.endsAt,
        specifiedType: const FullType(DateTime),
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
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.durationMinutesAtBooking != null) {
      yield r'durationMinutesAtBooking';
      yield serializers.serialize(
        object.durationMinutesAtBooking,
        specifiedType: const FullType(int),
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
    BookingResponse object, {
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
    required BookingResponseBuilder result,
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
        case r'clientId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientId = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'masterServiceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterServiceId = valueDes;
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
            specifiedType: const FullType(BookingResponseStatusEnum),
          ) as BookingResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'endsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.endsAt = valueDes;
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
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.priceMaxAtBooking = valueDes;
          break;
        case r'durationMinutesAtBooking':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMinutesAtBooking = valueDes;
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
  BookingResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingResponseBuilder();
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

class BookingResponseStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const BookingResponseStatusEnum CONFIRMED =
      _$bookingResponseStatusEnum_CONFIRMED;
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const BookingResponseStatusEnum DECLINED =
      _$bookingResponseStatusEnum_DECLINED;
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const BookingResponseStatusEnum COMPLETED =
      _$bookingResponseStatusEnum_COMPLETED;
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const BookingResponseStatusEnum NOT_COMPLETED =
      _$bookingResponseStatusEnum_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const BookingResponseStatusEnum CANCELLED =
      _$bookingResponseStatusEnum_CANCELLED;

  static Serializer<BookingResponseStatusEnum> get serializer =>
      _$bookingResponseStatusEnumSerializer;

  const BookingResponseStatusEnum._(String name) : super(name);

  static BuiltSet<BookingResponseStatusEnum> get values =>
      _$bookingResponseStatusEnumValues;
  static BookingResponseStatusEnum valueOf(String name) =>
      _$bookingResponseStatusEnumValueOf(name);
}
