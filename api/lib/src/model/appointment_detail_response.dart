//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/appointment_item_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appointment_detail_response.g.dart';

/// AppointmentDetailResponse
///
/// Properties:
/// * [id]
/// * [status]
/// * [masterId]
/// * [masterFirstName]
/// * [masterLastName]
/// * [masterProfessionalTitle] - The master's professional title/headline. Nullable — a master may never have set one.
/// * [masterAvatarUrl]
/// * [masterType]
/// * [salonName] - The salon name, or null for an independent master.
/// * [startsAt]
/// * [endsAt]
/// * [totalDurationMinutes]
/// * [totalPrice]
/// * [totalPriceMax] - The summed range ceiling of the visit, present ONLY when at least one service was a genuine range at booking time. Null means a single total price — render totalPrice alone. Never re-derived on read.
/// * [clientComment] - The client's booking-creation note for the whole visit.
/// * [createdAt]
/// * [items]
/// * [providerComment] - Written by the provider on the visit /decline or /not-complete. Shown to the CLIENT on both DECLINED and NOT_COMPLETED visits — intentional, by the locked \"all notes visible for all sides\" decision, NOT a privacy leak. Do not suppress for any audience. Same field/rule as BookingDetailResponse.providerComment, lifted to the visit header.
/// * [clientCancellationNote] - Written by the CLIENT on the visit /cancel — the symmetric counterpart of providerComment, shown to the provider. Only ever non-null on a CANCELLED visit. Same field/rule as BookingDetailResponse.clientCancellationNote.
/// * [cityLabel] - Discovery city label (Ukrainian). Resolved by the service through the same district-primary DiscoveryLocationResolver seam as BookingDetailResponse — salon locality when salon-employed, else the master's own user row.
/// * [districtLabel] - Discovery district label (Ukrainian). Same resolution as cityLabel.
/// * [street] - Arrival street — the salon's when salon-employed, else the master's own. Same salon-vs-independent rule as BookingDetailResponse.street; a salon-employed master's PERSONAL street never leaks onto a salon visit.
/// * [buildingNo] - Arrival building number.
/// * [locationNote] - Provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\"). Same salon-vs-independent resolution as street/buildingNo — a salon booking surfaces the salon's own note, never the master's personal one.
@BuiltValue()
abstract class AppointmentDetailResponse
    implements
        Built<AppointmentDetailResponse, AppointmentDetailResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'status')
  AppointmentDetailResponseStatusEnum? get status;
  // enum statusEnum {  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'masterFirstName')
  String? get masterFirstName;

  @BuiltValueField(wireName: r'masterLastName')
  String? get masterLastName;

  /// The master's professional title/headline. Nullable — a master may never have set one.
  @BuiltValueField(wireName: r'masterProfessionalTitle')
  String? get masterProfessionalTitle;

  @BuiltValueField(wireName: r'masterAvatarUrl')
  String? get masterAvatarUrl;

  @BuiltValueField(wireName: r'masterType')
  AppointmentDetailResponseMasterTypeEnum? get masterType;
  // enum masterTypeEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  /// The salon name, or null for an independent master.
  @BuiltValueField(wireName: r'salonName')
  String? get salonName;

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'endsAt')
  DateTime? get endsAt;

  @BuiltValueField(wireName: r'totalDurationMinutes')
  int? get totalDurationMinutes;

  @BuiltValueField(wireName: r'totalPrice')
  num? get totalPrice;

  /// The summed range ceiling of the visit, present ONLY when at least one service was a genuine range at booking time. Null means a single total price — render totalPrice alone. Never re-derived on read.
  @BuiltValueField(wireName: r'totalPriceMax')
  num? get totalPriceMax;

  /// The client's booking-creation note for the whole visit.
  @BuiltValueField(wireName: r'clientComment')
  String? get clientComment;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  @BuiltValueField(wireName: r'items')
  BuiltList<AppointmentItemResponse>? get items;

  /// Written by the provider on the visit /decline or /not-complete. Shown to the CLIENT on both DECLINED and NOT_COMPLETED visits — intentional, by the locked \"all notes visible for all sides\" decision, NOT a privacy leak. Do not suppress for any audience. Same field/rule as BookingDetailResponse.providerComment, lifted to the visit header.
  @BuiltValueField(wireName: r'providerComment')
  String? get providerComment;

  /// Written by the CLIENT on the visit /cancel — the symmetric counterpart of providerComment, shown to the provider. Only ever non-null on a CANCELLED visit. Same field/rule as BookingDetailResponse.clientCancellationNote.
  @BuiltValueField(wireName: r'clientCancellationNote')
  String? get clientCancellationNote;

  /// Discovery city label (Ukrainian). Resolved by the service through the same district-primary DiscoveryLocationResolver seam as BookingDetailResponse — salon locality when salon-employed, else the master's own user row.
  @BuiltValueField(wireName: r'cityLabel')
  String? get cityLabel;

  /// Discovery district label (Ukrainian). Same resolution as cityLabel.
  @BuiltValueField(wireName: r'districtLabel')
  String? get districtLabel;

  /// Arrival street — the salon's when salon-employed, else the master's own. Same salon-vs-independent rule as BookingDetailResponse.street; a salon-employed master's PERSONAL street never leaks onto a salon visit.
  @BuiltValueField(wireName: r'street')
  String? get street;

  /// Arrival building number.
  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  /// Provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\"). Same salon-vs-independent resolution as street/buildingNo — a salon booking surfaces the salon's own note, never the master's personal one.
  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  AppointmentDetailResponse._();

  factory AppointmentDetailResponse(
          [void updates(AppointmentDetailResponseBuilder b)]) =
      _$AppointmentDetailResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppointmentDetailResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppointmentDetailResponse> get serializer =>
      _$AppointmentDetailResponseSerializer();
}

class _$AppointmentDetailResponseSerializer
    implements PrimitiveSerializer<AppointmentDetailResponse> {
  @override
  final Iterable<Type> types = const [
    AppointmentDetailResponse,
    _$AppointmentDetailResponse
  ];

  @override
  final String wireName = r'AppointmentDetailResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppointmentDetailResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.status != null) {
      yield r'status';
      yield serializers.serialize(
        object.status,
        specifiedType: const FullType(AppointmentDetailResponseStatusEnum),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
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
        specifiedType: const FullType(AppointmentDetailResponseMasterTypeEnum),
      );
    }
    if (object.salonName != null) {
      yield r'salonName';
      yield serializers.serialize(
        object.salonName,
        specifiedType: const FullType.nullable(String),
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
    if (object.totalDurationMinutes != null) {
      yield r'totalDurationMinutes';
      yield serializers.serialize(
        object.totalDurationMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.totalPrice != null) {
      yield r'totalPrice';
      yield serializers.serialize(
        object.totalPrice,
        specifiedType: const FullType(num),
      );
    }
    if (object.totalPriceMax != null) {
      yield r'totalPriceMax';
      yield serializers.serialize(
        object.totalPriceMax,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.clientComment != null) {
      yield r'clientComment';
      yield serializers.serialize(
        object.clientComment,
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
    if (object.items != null) {
      yield r'items';
      yield serializers.serialize(
        object.items,
        specifiedType:
            const FullType(BuiltList, [FullType(AppointmentItemResponse)]),
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
    if (object.cityLabel != null) {
      yield r'cityLabel';
      yield serializers.serialize(
        object.cityLabel,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.districtLabel != null) {
      yield r'districtLabel';
      yield serializers.serialize(
        object.districtLabel,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.street != null) {
      yield r'street';
      yield serializers.serialize(
        object.street,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.buildingNo != null) {
      yield r'buildingNo';
      yield serializers.serialize(
        object.buildingNo,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AppointmentDetailResponse object, {
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
    required AppointmentDetailResponseBuilder result,
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
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AppointmentDetailResponseStatusEnum),
          ) as AppointmentDetailResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
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
            specifiedType:
                const FullType(AppointmentDetailResponseMasterTypeEnum),
          ) as AppointmentDetailResponseMasterTypeEnum;
          result.masterType = valueDes;
          break;
        case r'salonName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.salonName = valueDes;
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
        case r'totalDurationMinutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalDurationMinutes = valueDes;
          break;
        case r'totalPrice':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.totalPrice = valueDes;
          break;
        case r'totalPriceMax':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.totalPriceMax = valueDes;
          break;
        case r'clientComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.clientComment = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(AppointmentItemResponse)]),
          ) as BuiltList<AppointmentItemResponse>;
          result.items.replace(valueDes);
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
        case r'cityLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.cityLabel = valueDes;
          break;
        case r'districtLabel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.districtLabel = valueDes;
          break;
        case r'street':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.street = valueDes;
          break;
        case r'buildingNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppointmentDetailResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppointmentDetailResponseBuilder();
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

class AppointmentDetailResponseStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const AppointmentDetailResponseStatusEnum CONFIRMED =
      _$appointmentDetailResponseStatusEnum_CONFIRMED;
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const AppointmentDetailResponseStatusEnum DECLINED =
      _$appointmentDetailResponseStatusEnum_DECLINED;
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const AppointmentDetailResponseStatusEnum COMPLETED =
      _$appointmentDetailResponseStatusEnum_COMPLETED;
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const AppointmentDetailResponseStatusEnum NOT_COMPLETED =
      _$appointmentDetailResponseStatusEnum_NOT_COMPLETED;
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const AppointmentDetailResponseStatusEnum CANCELLED =
      _$appointmentDetailResponseStatusEnum_CANCELLED;

  static Serializer<AppointmentDetailResponseStatusEnum> get serializer =>
      _$appointmentDetailResponseStatusEnumSerializer;

  const AppointmentDetailResponseStatusEnum._(String name) : super(name);

  static BuiltSet<AppointmentDetailResponseStatusEnum> get values =>
      _$appointmentDetailResponseStatusEnumValues;
  static AppointmentDetailResponseStatusEnum valueOf(String name) =>
      _$appointmentDetailResponseStatusEnumValueOf(name);
}

class AppointmentDetailResponseMasterTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const AppointmentDetailResponseMasterTypeEnum CLIENT =
      _$appointmentDetailResponseMasterTypeEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const AppointmentDetailResponseMasterTypeEnum SALON_OWNER =
      _$appointmentDetailResponseMasterTypeEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const AppointmentDetailResponseMasterTypeEnum SALON_ADMIN =
      _$appointmentDetailResponseMasterTypeEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const AppointmentDetailResponseMasterTypeEnum SALON_MASTER =
      _$appointmentDetailResponseMasterTypeEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const AppointmentDetailResponseMasterTypeEnum INDEPENDENT_MASTER =
      _$appointmentDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;

  static Serializer<AppointmentDetailResponseMasterTypeEnum> get serializer =>
      _$appointmentDetailResponseMasterTypeEnumSerializer;

  const AppointmentDetailResponseMasterTypeEnum._(String name) : super(name);

  static BuiltSet<AppointmentDetailResponseMasterTypeEnum> get values =>
      _$appointmentDetailResponseMasterTypeEnumValues;
  static AppointmentDetailResponseMasterTypeEnum valueOf(String name) =>
      _$appointmentDetailResponseMasterTypeEnumValueOf(name);
}
