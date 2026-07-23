// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_booking_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestBookingResponse extends GuestBookingResponse {
  @override
  final String? bookingId;
  @override
  final String? appointmentId;
  @override
  final DateTime? startsAt;
  @override
  final String? masterName;
  @override
  final String? serviceName;
  @override
  final int? durationMinutes;
  @override
  final String? cancelUrl;

  factory _$GuestBookingResponse(
          [void Function(GuestBookingResponseBuilder)? updates]) =>
      (GuestBookingResponseBuilder()..update(updates))._build();

  _$GuestBookingResponse._(
      {this.bookingId,
      this.appointmentId,
      this.startsAt,
      this.masterName,
      this.serviceName,
      this.durationMinutes,
      this.cancelUrl})
      : super._();
  @override
  GuestBookingResponse rebuild(
          void Function(GuestBookingResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestBookingResponseBuilder toBuilder() =>
      GuestBookingResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestBookingResponse &&
        bookingId == other.bookingId &&
        appointmentId == other.appointmentId &&
        startsAt == other.startsAt &&
        masterName == other.masterName &&
        serviceName == other.serviceName &&
        durationMinutes == other.durationMinutes &&
        cancelUrl == other.cancelUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, appointmentId.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, masterName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, durationMinutes.hashCode);
    _$hash = $jc(_$hash, cancelUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestBookingResponse')
          ..add('bookingId', bookingId)
          ..add('appointmentId', appointmentId)
          ..add('startsAt', startsAt)
          ..add('masterName', masterName)
          ..add('serviceName', serviceName)
          ..add('durationMinutes', durationMinutes)
          ..add('cancelUrl', cancelUrl))
        .toString();
  }
}

class GuestBookingResponseBuilder
    implements Builder<GuestBookingResponse, GuestBookingResponseBuilder> {
  _$GuestBookingResponse? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _appointmentId;
  String? get appointmentId => _$this._appointmentId;
  set appointmentId(String? appointmentId) =>
      _$this._appointmentId = appointmentId;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  String? _masterName;
  String? get masterName => _$this._masterName;
  set masterName(String? masterName) => _$this._masterName = masterName;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  int? _durationMinutes;
  int? get durationMinutes => _$this._durationMinutes;
  set durationMinutes(int? durationMinutes) =>
      _$this._durationMinutes = durationMinutes;

  String? _cancelUrl;
  String? get cancelUrl => _$this._cancelUrl;
  set cancelUrl(String? cancelUrl) => _$this._cancelUrl = cancelUrl;

  GuestBookingResponseBuilder() {
    GuestBookingResponse._defaults(this);
  }

  GuestBookingResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _appointmentId = $v.appointmentId;
      _startsAt = $v.startsAt;
      _masterName = $v.masterName;
      _serviceName = $v.serviceName;
      _durationMinutes = $v.durationMinutes;
      _cancelUrl = $v.cancelUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestBookingResponse other) {
    _$v = other as _$GuestBookingResponse;
  }

  @override
  void update(void Function(GuestBookingResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestBookingResponse build() => _build();

  _$GuestBookingResponse _build() {
    final _$result = _$v ??
        _$GuestBookingResponse._(
          bookingId: bookingId,
          appointmentId: appointmentId,
          startsAt: startsAt,
          masterName: masterName,
          serviceName: serviceName,
          durationMinutes: durationMinutes,
          cancelUrl: cancelUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
