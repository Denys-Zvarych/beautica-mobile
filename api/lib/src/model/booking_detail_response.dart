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
/// * [priceMaxAtBooking] - The range ceiling agreed AT BOOKING TIME, present ONLY when the master left this service's price as a genuine RANGE (no priceOverride) when the booking was made. Null means a single price — render priceAtBooking alone. The client must never re-derive this from priceType/priceOverride; the decision is made server-side, once.
/// * [durationMinutesAtBooking]
/// * [createdAt]
/// * [clientFirstName]
/// * [clientLastName]
/// * [masterFirstName]
/// * [masterLastName]
/// * [masterProfessionalTitle] - The master's professional title/headline (e.g. \"Перукар-стиліст\"), same field as MasterSummaryResponse/MasterDetailResponse. Nullable — a master may never have set one.
/// * [clientComment] - The client's booking-creation note (written once at POST /bookings). Visible to the provider. Distinct from clientCancellationNote below — this is NOT the cancellation reason.
/// * [providerComment] - Written by the provider on /decline or /not-complete. Visible to the CLIENT on both DECLINED and NOT_COMPLETED bookings — intentional, by locked product decision (\"all notes visible for all sides\"), NOT a privacy leak. Do not suppress this for any audience.
/// * [clientCancellationNote] - Written by the CLIENT on /cancel. Visible to the provider — the symmetric counterpart of providerComment. Only ever non-null on a CANCELLED booking.
/// * [masterAvatarUrl]
/// * [masterType]
/// * [salonName]
/// * [cityLabel]
/// * [districtLabel]
/// * [street]
/// * [buildingNo]
/// * [locationNote] - The provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\", \"вхід з двору, дзвонити двічі\"). Resolved by the identical salon-vs-independent rule as street/buildingNo: a salon booking surfaces the salon's own note, an independent master surfaces their own note. Nullable — most providers never set one.
/// * [categoryName]
/// * [canReview]
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

  @BuiltValueField(wireName: r'clientFirstName')
  String? get clientFirstName;

  @BuiltValueField(wireName: r'clientLastName')
  String? get clientLastName;

  @BuiltValueField(wireName: r'masterFirstName')
  String? get masterFirstName;

  @BuiltValueField(wireName: r'masterLastName')
  String? get masterLastName;

  /// The master's professional title/headline (e.g. \"Перукар-стиліст\"), same field as MasterSummaryResponse/MasterDetailResponse. Nullable — a master may never have set one.
  @BuiltValueField(wireName: r'masterProfessionalTitle')
  String? get masterProfessionalTitle;

  /// The client's booking-creation note (written once at POST /bookings). Visible to the provider. Distinct from clientCancellationNote below — this is NOT the cancellation reason.
  @BuiltValueField(wireName: r'clientComment')
  String? get clientComment;

  /// Written by the provider on /decline or /not-complete. Visible to the CLIENT on both DECLINED and NOT_COMPLETED bookings — intentional, by locked product decision (\"all notes visible for all sides\"), NOT a privacy leak. Do not suppress this for any audience.
  @BuiltValueField(wireName: r'providerComment')
  String? get providerComment;

  /// Written by the CLIENT on /cancel. Visible to the provider — the symmetric counterpart of providerComment. Only ever non-null on a CANCELLED booking.
  @BuiltValueField(wireName: r'clientCancellationNote')
  String? get clientCancellationNote;

  @BuiltValueField(wireName: r'masterAvatarUrl')
  String? get masterAvatarUrl;

  @BuiltValueField(wireName: r'masterType')
  BookingDetailResponseMasterTypeEnum? get masterType;
  // enum masterTypeEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  @BuiltValueField(wireName: r'salonName')
  String? get salonName;

  @BuiltValueField(wireName: r'cityLabel')
  String? get cityLabel;

  @BuiltValueField(wireName: r'districtLabel')
  String? get districtLabel;

  @BuiltValueField(wireName: r'street')
  String? get street;

  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  /// The provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\", \"вхід з двору, дзвонити двічі\"). Resolved by the identical salon-vs-independent rule as street/buildingNo: a salon booking surfaces the salon's own note, an independent master surfaces their own note. Nullable — most providers never set one.
  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  @BuiltValueField(wireName: r'categoryName')
  String? get categoryName;

  @BuiltValueField(wireName: r'canReview')
  bool? get canReview;

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
    if (object.masterProfessionalTitle != null) {
      yield r'masterProfessionalTitle';
      yield serializers.serialize(
        object.masterProfessionalTitle,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.clientComment != null) {
      yield r'clientComment';
      yield serializers.serialize(
        object.clientComment,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.providerComment != null) {
      yield r'providerComment';
      yield serializers.serialize(
        object.providerComment,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.clientCancellationNote != null) {
      yield r'clientCancellationNote';
      yield serializers.serialize(
        object.clientCancellationNote,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.masterAvatarUrl != null) {
      yield r'masterAvatarUrl';
      yield serializers.serialize(
        object.masterAvatarUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterType != null) {
      yield r'masterType';
      yield serializers.serialize(
        object.masterType,
        specifiedType: const FullType(BookingDetailResponseMasterTypeEnum),
      );
    }
    if (object.salonName != null) {
      yield r'salonName';
      yield serializers.serialize(
        object.salonName,
        specifiedType: const FullType(String),
      );
    }
    if (object.cityLabel != null) {
      yield r'cityLabel';
      yield serializers.serialize(
        object.cityLabel,
        specifiedType: const FullType(String),
      );
    }
    if (object.districtLabel != null) {
      yield r'districtLabel';
      yield serializers.serialize(
        object.districtLabel,
        specifiedType: const FullType(String),
      );
    }
    if (object.street != null) {
      yield r'street';
      yield serializers.serialize(
        object.street,
        specifiedType: const FullType(String),
      );
    }
    if (object.buildingNo != null) {
      yield r'buildingNo';
      yield serializers.serialize(
        object.buildingNo,
        specifiedType: const FullType(String),
      );
    }
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.categoryName != null) {
      yield r'categoryName';
      yield serializers.serialize(
        object.categoryName,
        specifiedType: const FullType(String),
      );
    }
    if (object.canReview != null) {
      yield r'canReview';
      yield serializers.serialize(
        object.canReview,
        specifiedType: const FullType(bool),
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
        case r'masterProfessionalTitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.masterProfessionalTitle = valueDes;
          break;
        case r'clientComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.clientComment = valueDes;
          break;
        case r'providerComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.providerComment = valueDes;
          break;
        case r'clientCancellationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.clientCancellationNote = valueDes;
          break;
        case r'masterAvatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterAvatarUrl = valueDes;
          break;
        case r'masterType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingDetailResponseMasterTypeEnum),
          ) as BookingDetailResponseMasterTypeEnum;
          result.masterType = valueDes;
          break;
        case r'salonName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.salonName = valueDes;
          break;
        case r'cityLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityLabel = valueDes;
          break;
        case r'districtLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.districtLabel = valueDes;
          break;
        case r'street':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.street = valueDes;
          break;
        case r'buildingNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.buildingNo = valueDes;
          break;
        case r'locationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.locationNote = valueDes;
          break;
        case r'categoryName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.categoryName = valueDes;
          break;
        case r'canReview':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.canReview = valueDes;
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

class BookingDetailResponseMasterTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const BookingDetailResponseMasterTypeEnum CLIENT =
      _$bookingDetailResponseMasterTypeEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const BookingDetailResponseMasterTypeEnum SALON_OWNER =
      _$bookingDetailResponseMasterTypeEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const BookingDetailResponseMasterTypeEnum SALON_ADMIN =
      _$bookingDetailResponseMasterTypeEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const BookingDetailResponseMasterTypeEnum SALON_MASTER =
      _$bookingDetailResponseMasterTypeEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const BookingDetailResponseMasterTypeEnum INDEPENDENT_MASTER =
      _$bookingDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;

  static Serializer<BookingDetailResponseMasterTypeEnum> get serializer =>
      _$bookingDetailResponseMasterTypeEnumSerializer;

  const BookingDetailResponseMasterTypeEnum._(String name) : super(name);

  static BuiltSet<BookingDetailResponseMasterTypeEnum> get values =>
      _$bookingDetailResponseMasterTypeEnumValues;
  static BookingDetailResponseMasterTypeEnum valueOf(String name) =>
      _$bookingDetailResponseMasterTypeEnumValueOf(name);
}
