// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'override_conflict_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OverrideConflictResponse extends OverrideConflictResponse {
  @override
  final String? bookingId;
  @override
  final String? appointmentId;
  @override
  final Date? date;
  @override
  final DateTime? startsAt;
  @override
  final DateTime? endsAt;
  @override
  final String? clientDisplayName;
  @override
  final String? serviceName;

  factory _$OverrideConflictResponse(
          [void Function(OverrideConflictResponseBuilder)? updates]) =>
      (OverrideConflictResponseBuilder()..update(updates))._build();

  _$OverrideConflictResponse._(
      {this.bookingId,
      this.appointmentId,
      this.date,
      this.startsAt,
      this.endsAt,
      this.clientDisplayName,
      this.serviceName})
      : super._();
  @override
  OverrideConflictResponse rebuild(
          void Function(OverrideConflictResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OverrideConflictResponseBuilder toBuilder() =>
      OverrideConflictResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OverrideConflictResponse &&
        bookingId == other.bookingId &&
        appointmentId == other.appointmentId &&
        date == other.date &&
        startsAt == other.startsAt &&
        endsAt == other.endsAt &&
        clientDisplayName == other.clientDisplayName &&
        serviceName == other.serviceName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, appointmentId.hashCode);
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, endsAt.hashCode);
    _$hash = $jc(_$hash, clientDisplayName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OverrideConflictResponse')
          ..add('bookingId', bookingId)
          ..add('appointmentId', appointmentId)
          ..add('date', date)
          ..add('startsAt', startsAt)
          ..add('endsAt', endsAt)
          ..add('clientDisplayName', clientDisplayName)
          ..add('serviceName', serviceName))
        .toString();
  }
}

class OverrideConflictResponseBuilder
    implements
        Builder<OverrideConflictResponse, OverrideConflictResponseBuilder> {
  _$OverrideConflictResponse? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _appointmentId;
  String? get appointmentId => _$this._appointmentId;
  set appointmentId(String? appointmentId) =>
      _$this._appointmentId = appointmentId;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  DateTime? _endsAt;
  DateTime? get endsAt => _$this._endsAt;
  set endsAt(DateTime? endsAt) => _$this._endsAt = endsAt;

  String? _clientDisplayName;
  String? get clientDisplayName => _$this._clientDisplayName;
  set clientDisplayName(String? clientDisplayName) =>
      _$this._clientDisplayName = clientDisplayName;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  OverrideConflictResponseBuilder() {
    OverrideConflictResponse._defaults(this);
  }

  OverrideConflictResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _appointmentId = $v.appointmentId;
      _date = $v.date;
      _startsAt = $v.startsAt;
      _endsAt = $v.endsAt;
      _clientDisplayName = $v.clientDisplayName;
      _serviceName = $v.serviceName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OverrideConflictResponse other) {
    _$v = other as _$OverrideConflictResponse;
  }

  @override
  void update(void Function(OverrideConflictResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OverrideConflictResponse build() => _build();

  _$OverrideConflictResponse _build() {
    final _$result = _$v ??
        _$OverrideConflictResponse._(
          bookingId: bookingId,
          appointmentId: appointmentId,
          date: date,
          startsAt: startsAt,
          endsAt: endsAt,
          clientDisplayName: clientDisplayName,
          serviceName: serviceName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
