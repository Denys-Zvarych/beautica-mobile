// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AppointmentItemResponseStatusEnum
    _$appointmentItemResponseStatusEnum_CONFIRMED =
    const AppointmentItemResponseStatusEnum._('CONFIRMED');
const AppointmentItemResponseStatusEnum
    _$appointmentItemResponseStatusEnum_DECLINED =
    const AppointmentItemResponseStatusEnum._('DECLINED');
const AppointmentItemResponseStatusEnum
    _$appointmentItemResponseStatusEnum_COMPLETED =
    const AppointmentItemResponseStatusEnum._('COMPLETED');
const AppointmentItemResponseStatusEnum
    _$appointmentItemResponseStatusEnum_NOT_COMPLETED =
    const AppointmentItemResponseStatusEnum._('NOT_COMPLETED');
const AppointmentItemResponseStatusEnum
    _$appointmentItemResponseStatusEnum_CANCELLED =
    const AppointmentItemResponseStatusEnum._('CANCELLED');

AppointmentItemResponseStatusEnum _$appointmentItemResponseStatusEnumValueOf(
    String name) {
  switch (name) {
    case 'CONFIRMED':
      return _$appointmentItemResponseStatusEnum_CONFIRMED;
    case 'DECLINED':
      return _$appointmentItemResponseStatusEnum_DECLINED;
    case 'COMPLETED':
      return _$appointmentItemResponseStatusEnum_COMPLETED;
    case 'NOT_COMPLETED':
      return _$appointmentItemResponseStatusEnum_NOT_COMPLETED;
    case 'CANCELLED':
      return _$appointmentItemResponseStatusEnum_CANCELLED;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AppointmentItemResponseStatusEnum>
    _$appointmentItemResponseStatusEnumValues = BuiltSet<
        AppointmentItemResponseStatusEnum>(const <AppointmentItemResponseStatusEnum>[
  _$appointmentItemResponseStatusEnum_CONFIRMED,
  _$appointmentItemResponseStatusEnum_DECLINED,
  _$appointmentItemResponseStatusEnum_COMPLETED,
  _$appointmentItemResponseStatusEnum_NOT_COMPLETED,
  _$appointmentItemResponseStatusEnum_CANCELLED,
]);

const AppointmentItemResponseCancellationReasonEnum
    _$appointmentItemResponseCancellationReasonEnum_CLIENT_NO_SHOW =
    const AppointmentItemResponseCancellationReasonEnum._('CLIENT_NO_SHOW');
const AppointmentItemResponseCancellationReasonEnum
    _$appointmentItemResponseCancellationReasonEnum_CLIENT_CANCELLED =
    const AppointmentItemResponseCancellationReasonEnum._('CLIENT_CANCELLED');
const AppointmentItemResponseCancellationReasonEnum
    _$appointmentItemResponseCancellationReasonEnum_PROVIDER_UNAVAILABLE =
    const AppointmentItemResponseCancellationReasonEnum._(
        'PROVIDER_UNAVAILABLE');
const AppointmentItemResponseCancellationReasonEnum
    _$appointmentItemResponseCancellationReasonEnum_DUPLICATE =
    const AppointmentItemResponseCancellationReasonEnum._('DUPLICATE');
const AppointmentItemResponseCancellationReasonEnum
    _$appointmentItemResponseCancellationReasonEnum_OTHER =
    const AppointmentItemResponseCancellationReasonEnum._('OTHER');

AppointmentItemResponseCancellationReasonEnum
    _$appointmentItemResponseCancellationReasonEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT_NO_SHOW':
      return _$appointmentItemResponseCancellationReasonEnum_CLIENT_NO_SHOW;
    case 'CLIENT_CANCELLED':
      return _$appointmentItemResponseCancellationReasonEnum_CLIENT_CANCELLED;
    case 'PROVIDER_UNAVAILABLE':
      return _$appointmentItemResponseCancellationReasonEnum_PROVIDER_UNAVAILABLE;
    case 'DUPLICATE':
      return _$appointmentItemResponseCancellationReasonEnum_DUPLICATE;
    case 'OTHER':
      return _$appointmentItemResponseCancellationReasonEnum_OTHER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AppointmentItemResponseCancellationReasonEnum>
    _$appointmentItemResponseCancellationReasonEnumValues = BuiltSet<
        AppointmentItemResponseCancellationReasonEnum>(const <AppointmentItemResponseCancellationReasonEnum>[
  _$appointmentItemResponseCancellationReasonEnum_CLIENT_NO_SHOW,
  _$appointmentItemResponseCancellationReasonEnum_CLIENT_CANCELLED,
  _$appointmentItemResponseCancellationReasonEnum_PROVIDER_UNAVAILABLE,
  _$appointmentItemResponseCancellationReasonEnum_DUPLICATE,
  _$appointmentItemResponseCancellationReasonEnum_OTHER,
]);

Serializer<AppointmentItemResponseStatusEnum>
    _$appointmentItemResponseStatusEnumSerializer =
    _$AppointmentItemResponseStatusEnumSerializer();
Serializer<AppointmentItemResponseCancellationReasonEnum>
    _$appointmentItemResponseCancellationReasonEnumSerializer =
    _$AppointmentItemResponseCancellationReasonEnumSerializer();

class _$AppointmentItemResponseStatusEnumSerializer
    implements PrimitiveSerializer<AppointmentItemResponseStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
  };

  @override
  final Iterable<Type> types = const <Type>[AppointmentItemResponseStatusEnum];
  @override
  final String wireName = 'AppointmentItemResponseStatusEnum';

  @override
  Object serialize(
          Serializers serializers, AppointmentItemResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AppointmentItemResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AppointmentItemResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AppointmentItemResponseCancellationReasonEnumSerializer
    implements
        PrimitiveSerializer<AppointmentItemResponseCancellationReasonEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CLIENT_NO_SHOW': 'CLIENT_NO_SHOW',
    'CLIENT_CANCELLED': 'CLIENT_CANCELLED',
    'PROVIDER_UNAVAILABLE': 'PROVIDER_UNAVAILABLE',
    'DUPLICATE': 'DUPLICATE',
    'OTHER': 'OTHER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CLIENT_NO_SHOW': 'CLIENT_NO_SHOW',
    'CLIENT_CANCELLED': 'CLIENT_CANCELLED',
    'PROVIDER_UNAVAILABLE': 'PROVIDER_UNAVAILABLE',
    'DUPLICATE': 'DUPLICATE',
    'OTHER': 'OTHER',
  };

  @override
  final Iterable<Type> types = const <Type>[
    AppointmentItemResponseCancellationReasonEnum
  ];
  @override
  final String wireName = 'AppointmentItemResponseCancellationReasonEnum';

  @override
  Object serialize(Serializers serializers,
          AppointmentItemResponseCancellationReasonEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AppointmentItemResponseCancellationReasonEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AppointmentItemResponseCancellationReasonEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AppointmentItemResponse extends AppointmentItemResponse {
  @override
  final String? bookingId;
  @override
  final String? masterServiceId;
  @override
  final String? serviceName;
  @override
  final AppointmentItemResponseStatusEnum? status;
  @override
  final DateTime? startsAt;
  @override
  final DateTime? endsAt;
  @override
  final int? durationMinutesAtBooking;
  @override
  final num? priceAtBooking;
  @override
  final num? priceMaxAtBooking;
  @override
  final AppointmentItemResponseCancellationReasonEnum? cancellationReason;
  @override
  final String? providerComment;

  factory _$AppointmentItemResponse(
          [void Function(AppointmentItemResponseBuilder)? updates]) =>
      (AppointmentItemResponseBuilder()..update(updates))._build();

  _$AppointmentItemResponse._(
      {this.bookingId,
      this.masterServiceId,
      this.serviceName,
      this.status,
      this.startsAt,
      this.endsAt,
      this.durationMinutesAtBooking,
      this.priceAtBooking,
      this.priceMaxAtBooking,
      this.cancellationReason,
      this.providerComment})
      : super._();
  @override
  AppointmentItemResponse rebuild(
          void Function(AppointmentItemResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppointmentItemResponseBuilder toBuilder() =>
      AppointmentItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppointmentItemResponse &&
        bookingId == other.bookingId &&
        masterServiceId == other.masterServiceId &&
        serviceName == other.serviceName &&
        status == other.status &&
        startsAt == other.startsAt &&
        endsAt == other.endsAt &&
        durationMinutesAtBooking == other.durationMinutesAtBooking &&
        priceAtBooking == other.priceAtBooking &&
        priceMaxAtBooking == other.priceMaxAtBooking &&
        cancellationReason == other.cancellationReason &&
        providerComment == other.providerComment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, masterServiceId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, endsAt.hashCode);
    _$hash = $jc(_$hash, durationMinutesAtBooking.hashCode);
    _$hash = $jc(_$hash, priceAtBooking.hashCode);
    _$hash = $jc(_$hash, priceMaxAtBooking.hashCode);
    _$hash = $jc(_$hash, cancellationReason.hashCode);
    _$hash = $jc(_$hash, providerComment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppointmentItemResponse')
          ..add('bookingId', bookingId)
          ..add('masterServiceId', masterServiceId)
          ..add('serviceName', serviceName)
          ..add('status', status)
          ..add('startsAt', startsAt)
          ..add('endsAt', endsAt)
          ..add('durationMinutesAtBooking', durationMinutesAtBooking)
          ..add('priceAtBooking', priceAtBooking)
          ..add('priceMaxAtBooking', priceMaxAtBooking)
          ..add('cancellationReason', cancellationReason)
          ..add('providerComment', providerComment))
        .toString();
  }
}

class AppointmentItemResponseBuilder
    implements
        Builder<AppointmentItemResponse, AppointmentItemResponseBuilder> {
  _$AppointmentItemResponse? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _masterServiceId;
  String? get masterServiceId => _$this._masterServiceId;
  set masterServiceId(String? masterServiceId) =>
      _$this._masterServiceId = masterServiceId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  AppointmentItemResponseStatusEnum? _status;
  AppointmentItemResponseStatusEnum? get status => _$this._status;
  set status(AppointmentItemResponseStatusEnum? status) =>
      _$this._status = status;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  DateTime? _endsAt;
  DateTime? get endsAt => _$this._endsAt;
  set endsAt(DateTime? endsAt) => _$this._endsAt = endsAt;

  int? _durationMinutesAtBooking;
  int? get durationMinutesAtBooking => _$this._durationMinutesAtBooking;
  set durationMinutesAtBooking(int? durationMinutesAtBooking) =>
      _$this._durationMinutesAtBooking = durationMinutesAtBooking;

  num? _priceAtBooking;
  num? get priceAtBooking => _$this._priceAtBooking;
  set priceAtBooking(num? priceAtBooking) =>
      _$this._priceAtBooking = priceAtBooking;

  num? _priceMaxAtBooking;
  num? get priceMaxAtBooking => _$this._priceMaxAtBooking;
  set priceMaxAtBooking(num? priceMaxAtBooking) =>
      _$this._priceMaxAtBooking = priceMaxAtBooking;

  AppointmentItemResponseCancellationReasonEnum? _cancellationReason;
  AppointmentItemResponseCancellationReasonEnum? get cancellationReason =>
      _$this._cancellationReason;
  set cancellationReason(
          AppointmentItemResponseCancellationReasonEnum? cancellationReason) =>
      _$this._cancellationReason = cancellationReason;

  String? _providerComment;
  String? get providerComment => _$this._providerComment;
  set providerComment(String? providerComment) =>
      _$this._providerComment = providerComment;

  AppointmentItemResponseBuilder() {
    AppointmentItemResponse._defaults(this);
  }

  AppointmentItemResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _masterServiceId = $v.masterServiceId;
      _serviceName = $v.serviceName;
      _status = $v.status;
      _startsAt = $v.startsAt;
      _endsAt = $v.endsAt;
      _durationMinutesAtBooking = $v.durationMinutesAtBooking;
      _priceAtBooking = $v.priceAtBooking;
      _priceMaxAtBooking = $v.priceMaxAtBooking;
      _cancellationReason = $v.cancellationReason;
      _providerComment = $v.providerComment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppointmentItemResponse other) {
    _$v = other as _$AppointmentItemResponse;
  }

  @override
  void update(void Function(AppointmentItemResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppointmentItemResponse build() => _build();

  _$AppointmentItemResponse _build() {
    final _$result = _$v ??
        _$AppointmentItemResponse._(
          bookingId: bookingId,
          masterServiceId: masterServiceId,
          serviceName: serviceName,
          status: status,
          startsAt: startsAt,
          endsAt: endsAt,
          durationMinutesAtBooking: durationMinutesAtBooking,
          priceAtBooking: priceAtBooking,
          priceMaxAtBooking: priceMaxAtBooking,
          cancellationReason: cancellationReason,
          providerComment: providerComment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
