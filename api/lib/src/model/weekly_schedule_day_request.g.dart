// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_schedule_day_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WeeklyScheduleDayRequest extends WeeklyScheduleDayRequest {
  @override
  final int? dayOfWeek;
  @override
  final BuiltList<WorkIntervalDto>? intervals;

  factory _$WeeklyScheduleDayRequest(
          [void Function(WeeklyScheduleDayRequestBuilder)? updates]) =>
      (WeeklyScheduleDayRequestBuilder()..update(updates))._build();

  _$WeeklyScheduleDayRequest._({this.dayOfWeek, this.intervals}) : super._();
  @override
  WeeklyScheduleDayRequest rebuild(
          void Function(WeeklyScheduleDayRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WeeklyScheduleDayRequestBuilder toBuilder() =>
      WeeklyScheduleDayRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WeeklyScheduleDayRequest &&
        dayOfWeek == other.dayOfWeek &&
        intervals == other.intervals;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, dayOfWeek.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WeeklyScheduleDayRequest')
          ..add('dayOfWeek', dayOfWeek)
          ..add('intervals', intervals))
        .toString();
  }
}

class WeeklyScheduleDayRequestBuilder
    implements
        Builder<WeeklyScheduleDayRequest, WeeklyScheduleDayRequestBuilder> {
  _$WeeklyScheduleDayRequest? _$v;

  int? _dayOfWeek;
  int? get dayOfWeek => _$this._dayOfWeek;
  set dayOfWeek(int? dayOfWeek) => _$this._dayOfWeek = dayOfWeek;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  WeeklyScheduleDayRequestBuilder() {
    WeeklyScheduleDayRequest._defaults(this);
  }

  WeeklyScheduleDayRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dayOfWeek = $v.dayOfWeek;
      _intervals = $v.intervals?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WeeklyScheduleDayRequest other) {
    _$v = other as _$WeeklyScheduleDayRequest;
  }

  @override
  void update(void Function(WeeklyScheduleDayRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WeeklyScheduleDayRequest build() => _build();

  _$WeeklyScheduleDayRequest _build() {
    _$WeeklyScheduleDayRequest _$result;
    try {
      _$result = _$v ??
          _$WeeklyScheduleDayRequest._(
            dayOfWeek: dayOfWeek,
            intervals: _intervals?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'intervals';
        _intervals?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'WeeklyScheduleDayRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
