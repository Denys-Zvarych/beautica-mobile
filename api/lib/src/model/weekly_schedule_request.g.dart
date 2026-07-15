// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_schedule_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WeeklyScheduleRequest extends WeeklyScheduleRequest {
  @override
  final Date validFrom;
  @override
  final Date? validTo;
  @override
  final BuiltList<WeeklyScheduleDayRequest>? days;
  @override
  final bool? daysUnique;
  @override
  final bool? windowOrdered;

  factory _$WeeklyScheduleRequest(
          [void Function(WeeklyScheduleRequestBuilder)? updates]) =>
      (WeeklyScheduleRequestBuilder()..update(updates))._build();

  _$WeeklyScheduleRequest._(
      {required this.validFrom,
      this.validTo,
      this.days,
      this.daysUnique,
      this.windowOrdered})
      : super._();
  @override
  WeeklyScheduleRequest rebuild(
          void Function(WeeklyScheduleRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WeeklyScheduleRequestBuilder toBuilder() =>
      WeeklyScheduleRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WeeklyScheduleRequest &&
        validFrom == other.validFrom &&
        validTo == other.validTo &&
        days == other.days &&
        daysUnique == other.daysUnique &&
        windowOrdered == other.windowOrdered;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, validFrom.hashCode);
    _$hash = $jc(_$hash, validTo.hashCode);
    _$hash = $jc(_$hash, days.hashCode);
    _$hash = $jc(_$hash, daysUnique.hashCode);
    _$hash = $jc(_$hash, windowOrdered.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WeeklyScheduleRequest')
          ..add('validFrom', validFrom)
          ..add('validTo', validTo)
          ..add('days', days)
          ..add('daysUnique', daysUnique)
          ..add('windowOrdered', windowOrdered))
        .toString();
  }
}

class WeeklyScheduleRequestBuilder
    implements Builder<WeeklyScheduleRequest, WeeklyScheduleRequestBuilder> {
  _$WeeklyScheduleRequest? _$v;

  Date? _validFrom;
  Date? get validFrom => _$this._validFrom;
  set validFrom(Date? validFrom) => _$this._validFrom = validFrom;

  Date? _validTo;
  Date? get validTo => _$this._validTo;
  set validTo(Date? validTo) => _$this._validTo = validTo;

  ListBuilder<WeeklyScheduleDayRequest>? _days;
  ListBuilder<WeeklyScheduleDayRequest> get days =>
      _$this._days ??= ListBuilder<WeeklyScheduleDayRequest>();
  set days(ListBuilder<WeeklyScheduleDayRequest>? days) => _$this._days = days;

  bool? _daysUnique;
  bool? get daysUnique => _$this._daysUnique;
  set daysUnique(bool? daysUnique) => _$this._daysUnique = daysUnique;

  bool? _windowOrdered;
  bool? get windowOrdered => _$this._windowOrdered;
  set windowOrdered(bool? windowOrdered) =>
      _$this._windowOrdered = windowOrdered;

  WeeklyScheduleRequestBuilder() {
    WeeklyScheduleRequest._defaults(this);
  }

  WeeklyScheduleRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _validFrom = $v.validFrom;
      _validTo = $v.validTo;
      _days = $v.days?.toBuilder();
      _daysUnique = $v.daysUnique;
      _windowOrdered = $v.windowOrdered;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WeeklyScheduleRequest other) {
    _$v = other as _$WeeklyScheduleRequest;
  }

  @override
  void update(void Function(WeeklyScheduleRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WeeklyScheduleRequest build() => _build();

  _$WeeklyScheduleRequest _build() {
    _$WeeklyScheduleRequest _$result;
    try {
      _$result = _$v ??
          _$WeeklyScheduleRequest._(
            validFrom: BuiltValueNullFieldError.checkNotNull(
                validFrom, r'WeeklyScheduleRequest', 'validFrom'),
            validTo: validTo,
            days: _days?.build(),
            daysUnique: daysUnique,
            windowOrdered: windowOrdered,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'days';
        _days?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'WeeklyScheduleRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
