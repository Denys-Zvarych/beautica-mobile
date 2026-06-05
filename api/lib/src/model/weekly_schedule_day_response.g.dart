// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_schedule_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WeeklyScheduleDayResponse extends WeeklyScheduleDayResponse {
  @override
  final int? dayOfWeek;
  @override
  final BuiltList<WorkIntervalDto>? intervals;

  factory _$WeeklyScheduleDayResponse(
          [void Function(WeeklyScheduleDayResponseBuilder)? updates]) =>
      (WeeklyScheduleDayResponseBuilder()..update(updates))._build();

  _$WeeklyScheduleDayResponse._({this.dayOfWeek, this.intervals}) : super._();
  @override
  WeeklyScheduleDayResponse rebuild(
          void Function(WeeklyScheduleDayResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WeeklyScheduleDayResponseBuilder toBuilder() =>
      WeeklyScheduleDayResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WeeklyScheduleDayResponse &&
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
    return (newBuiltValueToStringHelper(r'WeeklyScheduleDayResponse')
          ..add('dayOfWeek', dayOfWeek)
          ..add('intervals', intervals))
        .toString();
  }
}

class WeeklyScheduleDayResponseBuilder
    implements
        Builder<WeeklyScheduleDayResponse, WeeklyScheduleDayResponseBuilder> {
  _$WeeklyScheduleDayResponse? _$v;

  int? _dayOfWeek;
  int? get dayOfWeek => _$this._dayOfWeek;
  set dayOfWeek(int? dayOfWeek) => _$this._dayOfWeek = dayOfWeek;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  WeeklyScheduleDayResponseBuilder() {
    WeeklyScheduleDayResponse._defaults(this);
  }

  WeeklyScheduleDayResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dayOfWeek = $v.dayOfWeek;
      _intervals = $v.intervals?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WeeklyScheduleDayResponse other) {
    _$v = other as _$WeeklyScheduleDayResponse;
  }

  @override
  void update(void Function(WeeklyScheduleDayResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WeeklyScheduleDayResponse build() => _build();

  _$WeeklyScheduleDayResponse _build() {
    _$WeeklyScheduleDayResponse _$result;
    try {
      _$result = _$v ??
          _$WeeklyScheduleDayResponse._(
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
            r'WeeklyScheduleDayResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
