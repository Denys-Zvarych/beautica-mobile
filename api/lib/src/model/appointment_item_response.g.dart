// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppointmentItemResponse extends AppointmentItemResponse {
  @override
  final String? bookingId;
  @override
  final String? masterServiceId;
  @override
  final String? serviceName;
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

  factory _$AppointmentItemResponse(
          [void Function(AppointmentItemResponseBuilder)? updates]) =>
      (AppointmentItemResponseBuilder()..update(updates))._build();

  _$AppointmentItemResponse._(
      {this.bookingId,
      this.masterServiceId,
      this.serviceName,
      this.startsAt,
      this.endsAt,
      this.durationMinutesAtBooking,
      this.priceAtBooking,
      this.priceMaxAtBooking})
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
        startsAt == other.startsAt &&
        endsAt == other.endsAt &&
        durationMinutesAtBooking == other.durationMinutesAtBooking &&
        priceAtBooking == other.priceAtBooking &&
        priceMaxAtBooking == other.priceMaxAtBooking;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, masterServiceId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, endsAt.hashCode);
    _$hash = $jc(_$hash, durationMinutesAtBooking.hashCode);
    _$hash = $jc(_$hash, priceAtBooking.hashCode);
    _$hash = $jc(_$hash, priceMaxAtBooking.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppointmentItemResponse')
          ..add('bookingId', bookingId)
          ..add('masterServiceId', masterServiceId)
          ..add('serviceName', serviceName)
          ..add('startsAt', startsAt)
          ..add('endsAt', endsAt)
          ..add('durationMinutesAtBooking', durationMinutesAtBooking)
          ..add('priceAtBooking', priceAtBooking)
          ..add('priceMaxAtBooking', priceMaxAtBooking))
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

  AppointmentItemResponseBuilder() {
    AppointmentItemResponse._defaults(this);
  }

  AppointmentItemResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _masterServiceId = $v.masterServiceId;
      _serviceName = $v.serviceName;
      _startsAt = $v.startsAt;
      _endsAt = $v.endsAt;
      _durationMinutesAtBooking = $v.durationMinutesAtBooking;
      _priceAtBooking = $v.priceAtBooking;
      _priceMaxAtBooking = $v.priceMaxAtBooking;
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
          startsAt: startsAt,
          endsAt: endsAt,
          durationMinutesAtBooking: durationMinutesAtBooking,
          priceAtBooking: priceAtBooking,
          priceMaxAtBooking: priceMaxAtBooking,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
