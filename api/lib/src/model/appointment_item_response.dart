//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appointment_item_response.g.dart';

/// AppointmentItemResponse
///
/// Properties:
/// * [bookingId]
/// * [masterServiceId]
/// * [serviceName]
/// * [status] - The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked.
/// * [startsAt]
/// * [endsAt]
/// * [durationMinutesAtBooking]
/// * [priceAtBooking]
/// * [priceMaxAtBooking] - The frozen RANGE ceiling for this service, present only when it was a genuine range (no priceOverride) at booking time. Null = single price.
/// * [cancellationReason] - This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline).
/// * [providerComment] - Provider note written on THIS line's per-service decline. Mutually visible to the client (locked booking-notes decision). Null on a CONFIRMED line and on whole-visit terminations (whose note lives on the header).
@BuiltValue()
abstract class AppointmentItemResponse
    implements Built<AppointmentItemResponse, AppointmentItemResponseBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String? get bookingId;

  @BuiltValueField(wireName: r'masterServiceId')
  String? get masterServiceId;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  /// The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked.
  @BuiltValueField(wireName: r'status')
  AppointmentItemResponseStatusEnum? get status;
  // enum statusEnum {  CONFIRMED,  DECLINED,  COMPLETED,  NOT_COMPLETED,  CANCELLED,  };

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'endsAt')
  DateTime? get endsAt;

  @BuiltValueField(wireName: r'durationMinutesAtBooking')
  int? get durationMinutesAtBooking;

  @BuiltValueField(wireName: r'priceAtBooking')
  num? get priceAtBooking;

  /// The frozen RANGE ceiling for this service, present only when it was a genuine range (no priceOverride) at booking time. Null = single price.
  @BuiltValueField(wireName: r'priceMaxAtBooking')
  num? get priceMaxAtBooking;

  /// This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline).
  @BuiltValueField(wireName: r'cancellationReason')
  AppointmentItemResponseCancellationReasonEnum? get cancellationReason;
  // enum cancellationReasonEnum {  CLIENT_NO_SHOW,  CLIENT_CANCELLED,  PROVIDER_UNAVAILABLE,  DUPLICATE,  OTHER,  };

  /// Provider note written on THIS line's per-service decline. Mutually visible to the client (locked booking-notes decision). Null on a CONFIRMED line and on whole-visit terminations (whose note lives on the header).
  @BuiltValueField(wireName: r'providerComment')
  String? get providerComment;

  AppointmentItemResponse._();

  factory AppointmentItemResponse(
          [void updates(AppointmentItemResponseBuilder b)]) =
      _$AppointmentItemResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppointmentItemResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppointmentItemResponse> get serializer =>
      _$AppointmentItemResponseSerializer();
}

class _$AppointmentItemResponseSerializer
    implements PrimitiveSerializer<AppointmentItemResponse> {
  @override
  final Iterable<Type> types = const [
    AppointmentItemResponse,
    _$AppointmentItemResponse
  ];

  @override
  final String wireName = r'AppointmentItemResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppointmentItemResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.bookingId != null) {
      yield r'bookingId';
      yield serializers.serialize(
        object.bookingId,
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
        specifiedType: const FullType(AppointmentItemResponseStatusEnum),
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
    if (object.durationMinutesAtBooking != null) {
      yield r'durationMinutesAtBooking';
      yield serializers.serialize(
        object.durationMinutesAtBooking,
        specifiedType: const FullType(int),
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
    if (object.cancellationReason != null) {
      yield r'cancellationReason';
      yield serializers.serialize(
        object.cancellationReason,
        specifiedType: const FullType.nullable(
            AppointmentItemResponseCancellationReasonEnum),
      );
    }
    if (object.providerComment != null) {
      yield r'providerComment';
      yield serializers.serialize(
        object.providerComment,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AppointmentItemResponse object, {
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
    required AppointmentItemResponseBuilder result,
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
            specifiedType: const FullType(AppointmentItemResponseStatusEnum),
          ) as AppointmentItemResponseStatusEnum;
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
        case r'durationMinutesAtBooking':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMinutesAtBooking = valueDes;
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
        case r'cancellationReason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(
                AppointmentItemResponseCancellationReasonEnum),
          ) as AppointmentItemResponseCancellationReasonEnum?;
          if (valueDes == null) continue;
          result.cancellationReason = valueDes;
          break;
        case r'providerComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
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
  AppointmentItemResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppointmentItemResponseBuilder();
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

class AppointmentItemResponseStatusEnum extends EnumClass {
  /// The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked.
  @BuiltValueEnumConst(wireName: r'CONFIRMED')
  static const AppointmentItemResponseStatusEnum CONFIRMED =
      _$appointmentItemResponseStatusEnum_CONFIRMED;

  /// The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked.
  @BuiltValueEnumConst(wireName: r'DECLINED')
  static const AppointmentItemResponseStatusEnum DECLINED =
      _$appointmentItemResponseStatusEnum_DECLINED;

  /// The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked.
  @BuiltValueEnumConst(wireName: r'COMPLETED')
  static const AppointmentItemResponseStatusEnum COMPLETED =
      _$appointmentItemResponseStatusEnum_COMPLETED;

  /// The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked.
  @BuiltValueEnumConst(wireName: r'NOT_COMPLETED')
  static const AppointmentItemResponseStatusEnum NOT_COMPLETED =
      _$appointmentItemResponseStatusEnum_NOT_COMPLETED;

  /// The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked.
  @BuiltValueEnumConst(wireName: r'CANCELLED')
  static const AppointmentItemResponseStatusEnum CANCELLED =
      _$appointmentItemResponseStatusEnum_CANCELLED;

  static Serializer<AppointmentItemResponseStatusEnum> get serializer =>
      _$appointmentItemResponseStatusEnumSerializer;

  const AppointmentItemResponseStatusEnum._(String name) : super(name);

  static BuiltSet<AppointmentItemResponseStatusEnum> get values =>
      _$appointmentItemResponseStatusEnumValues;
  static AppointmentItemResponseStatusEnum valueOf(String name) =>
      _$appointmentItemResponseStatusEnumValueOf(name);
}

class AppointmentItemResponseCancellationReasonEnum extends EnumClass {
  /// This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline).
  @BuiltValueEnumConst(wireName: r'CLIENT_NO_SHOW')
  static const AppointmentItemResponseCancellationReasonEnum CLIENT_NO_SHOW =
      _$appointmentItemResponseCancellationReasonEnum_CLIENT_NO_SHOW;

  /// This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline).
  @BuiltValueEnumConst(wireName: r'CLIENT_CANCELLED')
  static const AppointmentItemResponseCancellationReasonEnum CLIENT_CANCELLED =
      _$appointmentItemResponseCancellationReasonEnum_CLIENT_CANCELLED;

  /// This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline).
  @BuiltValueEnumConst(wireName: r'PROVIDER_UNAVAILABLE')
  static const AppointmentItemResponseCancellationReasonEnum
      PROVIDER_UNAVAILABLE =
      _$appointmentItemResponseCancellationReasonEnum_PROVIDER_UNAVAILABLE;

  /// This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline).
  @BuiltValueEnumConst(wireName: r'DUPLICATE')
  static const AppointmentItemResponseCancellationReasonEnum DUPLICATE =
      _$appointmentItemResponseCancellationReasonEnum_DUPLICATE;

  /// This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline).
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const AppointmentItemResponseCancellationReasonEnum OTHER =
      _$appointmentItemResponseCancellationReasonEnum_OTHER;

  static Serializer<AppointmentItemResponseCancellationReasonEnum>
      get serializer =>
          _$appointmentItemResponseCancellationReasonEnumSerializer;

  const AppointmentItemResponseCancellationReasonEnum._(String name)
      : super(name);

  static BuiltSet<AppointmentItemResponseCancellationReasonEnum> get values =>
      _$appointmentItemResponseCancellationReasonEnumValues;
  static AppointmentItemResponseCancellationReasonEnum valueOf(String name) =>
      _$appointmentItemResponseCancellationReasonEnumValueOf(name);
}
