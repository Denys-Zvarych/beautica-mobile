// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_schedule_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const WeeklyScheduleDayResponseModeEnum
    _$weeklyScheduleDayResponseModeEnum_INTERVAL =
    const WeeklyScheduleDayResponseModeEnum._('INTERVAL');
const WeeklyScheduleDayResponseModeEnum
    _$weeklyScheduleDayResponseModeEnum_EXPLICIT_TIMES =
    const WeeklyScheduleDayResponseModeEnum._('EXPLICIT_TIMES');

WeeklyScheduleDayResponseModeEnum _$weeklyScheduleDayResponseModeEnumValueOf(
    String name) {
  switch (name) {
    case 'INTERVAL':
      return _$weeklyScheduleDayResponseModeEnum_INTERVAL;
    case 'EXPLICIT_TIMES':
      return _$weeklyScheduleDayResponseModeEnum_EXPLICIT_TIMES;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<WeeklyScheduleDayResponseModeEnum>
    _$weeklyScheduleDayResponseModeEnumValues = BuiltSet<
        WeeklyScheduleDayResponseModeEnum>(const <WeeklyScheduleDayResponseModeEnum>[
  _$weeklyScheduleDayResponseModeEnum_INTERVAL,
  _$weeklyScheduleDayResponseModeEnum_EXPLICIT_TIMES,
]);

Serializer<WeeklyScheduleDayResponseModeEnum>
    _$weeklyScheduleDayResponseModeEnumSerializer =
    _$WeeklyScheduleDayResponseModeEnumSerializer();

class _$WeeklyScheduleDayResponseModeEnumSerializer
    implements PrimitiveSerializer<WeeklyScheduleDayResponseModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };

  @override
  final Iterable<Type> types = const <Type>[WeeklyScheduleDayResponseModeEnum];
  @override
  final String wireName = 'WeeklyScheduleDayResponseModeEnum';

  @override
  Object serialize(
          Serializers serializers, WeeklyScheduleDayResponseModeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  WeeklyScheduleDayResponseModeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      WeeklyScheduleDayResponseModeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$WeeklyScheduleDayResponse extends WeeklyScheduleDayResponse {
  @override
  final int? dayOfWeek;
  @override
  final WeeklyScheduleDayResponseModeEnum? mode;
  @override
  final BuiltList<WorkIntervalDto>? intervals;
  @override
  final BuiltList<String>? times;

  factory _$WeeklyScheduleDayResponse(
          [void Function(WeeklyScheduleDayResponseBuilder)? updates]) =>
      (WeeklyScheduleDayResponseBuilder()..update(updates))._build();

  _$WeeklyScheduleDayResponse._(
      {this.dayOfWeek, this.mode, this.intervals, this.times})
      : super._();
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
        mode == other.mode &&
        intervals == other.intervals &&
        times == other.times;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, dayOfWeek.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jc(_$hash, times.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WeeklyScheduleDayResponse')
          ..add('dayOfWeek', dayOfWeek)
          ..add('mode', mode)
          ..add('intervals', intervals)
          ..add('times', times))
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

  WeeklyScheduleDayResponseModeEnum? _mode;
  WeeklyScheduleDayResponseModeEnum? get mode => _$this._mode;
  set mode(WeeklyScheduleDayResponseModeEnum? mode) => _$this._mode = mode;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  ListBuilder<String>? _times;
  ListBuilder<String> get times => _$this._times ??= ListBuilder<String>();
  set times(ListBuilder<String>? times) => _$this._times = times;

  WeeklyScheduleDayResponseBuilder() {
    WeeklyScheduleDayResponse._defaults(this);
  }

  WeeklyScheduleDayResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dayOfWeek = $v.dayOfWeek;
      _mode = $v.mode;
      _intervals = $v.intervals?.toBuilder();
      _times = $v.times?.toBuilder();
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
            mode: mode,
            intervals: _intervals?.build(),
            times: _times?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'intervals';
        _intervals?.build();
        _$failedField = 'times';
        _times?.build();
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
