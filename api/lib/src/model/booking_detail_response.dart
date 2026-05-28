//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_detail_response.g.dart';

/// BookingDetailResponse
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
/// * [durationMinutesAtBooking]
/// * [createdAt]
/// * [clientFirstName]
/// * [clientLastName]
/// * [masterFirstName]
/// * [masterLastName]
/// * [clientComment]
/// * [providerComment]
@BuiltValue()
abstract class BookingDetailResponse
    implements Built<BookingDetailResponse, BookingDetailResponseBuilder> {
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
  BookingDetailResponseStatusEnum? get status;
  // enum statusEnum {  PENDING,  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'endsAt')
  DateTime? get endsAt;

  @BuiltValueField(wireName: r'priceAtBooking')
  num? get priceAtBooking;

  @BuiltValueField(wireName: r'durationMinutesAtBooking')
  int? get durationMinutesAtBooking;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  @BuiltValueField(wireName: r'clientFirstName')
  String? get clientFirstName;

  @BuiltValueField(wireName: r'clientLastName')
  String? get clientLastName;

  @BuiltValueField(wireName: r'masterFirstName')
  String? get masterFirstName;

  @BuiltValueField(wireName: r'masterLastName')
  String? get masterLastName;

  @BuiltValueField(wireName: r'clientComment')
  String? get clientComment;

  @BuiltValueField(wireName: r'providerComment')
  String? get providerComment;

  BookingDetailResponse._();

  factory BookingDetailResponse(
      [void updates(BookingDetailResponseBuilder b)]) = _$BookingDetailResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingDetailResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingDetailResponse> get serializer =>
      _$BookingDetailResponseSerializer();
}

class _$BookingDetailResponseSerializer
    implements PrimitiveSerializer<BookingDetailResponse> {
  @override
  final Iterable<Type> types = const [
    BookingDetailResponse,
    _$BookingDetailResponse
  ];

  @override
  final String wireName = r'BookingDetailResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingDetailResponse object, {
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
        specifiedType: const FullType(BookingDetailResponseStatusEnum),
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
    if (object.clientFirstName != null) {
      yield r'clientFirstName';
      yield serializers.serialize(
        object.clientFirstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.clientLastName != null) {
      yield r'clientLastName';
      yield serializers.serialize(
        object.clientLastName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterFirstName != null) {
      yield r'masterFirstName';
      yield serializers.serialize(
        object.masterFirstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterLastName != null) {
      yield r'masterLastName';
      yield serializers.serialize(
        object.masterLastName,
        specifiedType: const FullType(String),
      );
    }
    if (object.clientComment != null) {
      yield r'clientComment';
      yield serializers.serialize(
        object.clientComment,
        specifiedType: const FullType(String),
      );
    }
    if (object.providerComment != null) {
      yield r'providerComment';
      yield serializers.serialize(
        object.providerComment,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingDetailResponse object, {
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
    required BookingDetailResponseBuilder result,
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
            specifiedType: const FullType(BookingDetailResponseStatusEnum),
          ) as BookingDetailResponseStatusEnum;
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
        case r'clientFirstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientFirstName = valueDes;
          break;
        case r'clientLastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientLastName = valueDes;
          break;
        case r'masterFirstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterFirstName = valueDes;
          break;
        case r'masterLastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterLastName = valueDes;
          break;
        case r'clientComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientComment = valueDes;
          break;
        case r'providerComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.providerComment = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookingDetailResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingDetailResponseBuilder();
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

class BookingDetailResponseStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'PENDING')
  static const BookingDetailResponseStatusEnum PENDING =
      _$bookingDetailResponseStatusEnum_PENDING;
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const BookingDetailResponseStatusEnum CONFIRMED =
      _$bookingDetailResponseStatusEnum_CONFIRMED;
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const BookingDetailResponseStatusEnum DECLINED =
      _$bookingDetailResponseStatusEnum_DECLINED;
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const BookingDetailResponseStatusEnum COMPLETED =
      _$bookingDetailResponseStatusEnum_COMPLETED;
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const BookingDetailResponseStatusEnum NOT_COMPLETED =
      _$bookingDetailResponseStatusEnum_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const BookingDetailResponseStatusEnum CANCELLED =
      _$bookingDetailResponseStatusEnum_CANCELLED;

  static Serializer<BookingDetailResponseStatusEnum> get serializer =>
      _$bookingDetailResponseStatusEnumSerializer;

  const BookingDetailResponseStatusEnum._(String name) : super(name);

  static BuiltSet<BookingDetailResponseStatusEnum> get values =>
      _$bookingDetailResponseStatusEnumValues;
  static BookingDetailResponseStatusEnum valueOf(String name) =>
      _$bookingDetailResponseStatusEnumValueOf(name);
}
