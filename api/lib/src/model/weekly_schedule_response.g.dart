// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_schedule_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WeeklyScheduleResponse extends WeeklyScheduleResponse {
  @override
  final Date? validFrom;
  @override
  final Date? validTo;
  @override
  final BuiltList<WeeklyScheduleDayResponse>? days;

  factory _$WeeklyScheduleResponse(
          [void Function(WeeklyScheduleResponseBuilder)? updates]) =>
      (WeeklyScheduleResponseBuilder()..update(updates))._build();

  _$WeeklyScheduleResponse._({this.validFrom, this.validTo, this.days})
      : super._();
  @override
  WeeklyScheduleResponse rebuild(
          void Function(WeeklyScheduleResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WeeklyScheduleResponseBuilder toBuilder() =>
      WeeklyScheduleResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WeeklyScheduleResponse &&
        validFrom == other.validFrom &&
        validTo == other.validTo &&
        days == other.days;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, validFrom.hashCode);
    _$hash = $jc(_$hash, validTo.hashCode);
    _$hash = $jc(_$hash, days.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WeeklyScheduleResponse')
          ..add('validFrom', validFrom)
          ..add('validTo', validTo)
          ..add('days', days))
        .toString();
  }
}

class WeeklyScheduleResponseBuilder
    implements Builder<WeeklyScheduleResponse, WeeklyScheduleResponseBuilder> {
  _$WeeklyScheduleResponse? _$v;

  Date? _validFrom;
  Date? get validFrom => _$this._validFrom;
  set validFrom(Date? validFrom) => _$this._validFrom = validFrom;

  Date? _validTo;
  Date? get validTo => _$this._validTo;
  set validTo(Date? validTo) => _$this._validTo = validTo;

  ListBuilder<WeeklyScheduleDayResponse>? _days;
  ListBuilder<WeeklyScheduleDayResponse> get days =>
      _$this._days ??= ListBuilder<WeeklyScheduleDayResponse>();
  set days(ListBuilder<WeeklyScheduleDayResponse>? days) => _$this._days = days;

  WeeklyScheduleResponseBuilder() {
    WeeklyScheduleResponse._defaults(this);
  }

  WeeklyScheduleResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _validFrom = $v.validFrom;
      _validTo = $v.validTo;
      _days = $v.days?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WeeklyScheduleResponse other) {
    _$v = other as _$WeeklyScheduleResponse;
  }

  @override
  void update(void Function(WeeklyScheduleResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WeeklyScheduleResponse build() => _build();

  _$WeeklyScheduleResponse _build() {
    _$WeeklyScheduleResponse _$result;
    try {
      _$result = _$v ??
          _$WeeklyScheduleResponse._(
            validFrom: validFrom,
            validTo: validTo,
            days: _days?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'days';
        _days?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'WeeklyScheduleResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
