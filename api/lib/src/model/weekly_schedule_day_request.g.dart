// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_schedule_day_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const WeeklyScheduleDayRequestModeEnum
    _$weeklyScheduleDayRequestModeEnum_INTERVAL =
    const WeeklyScheduleDayRequestModeEnum._('INTERVAL');
const WeeklyScheduleDayRequestModeEnum
    _$weeklyScheduleDayRequestModeEnum_EXPLICIT_TIMES =
    const WeeklyScheduleDayRequestModeEnum._('EXPLICIT_TIMES');

WeeklyScheduleDayRequestModeEnum _$weeklyScheduleDayRequestModeEnumValueOf(
    String name) {
  switch (name) {
    case 'INTERVAL':
      return _$weeklyScheduleDayRequestModeEnum_INTERVAL;
    case 'EXPLICIT_TIMES':
      return _$weeklyScheduleDayRequestModeEnum_EXPLICIT_TIMES;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<WeeklyScheduleDayRequestModeEnum>
    _$weeklyScheduleDayRequestModeEnumValues = BuiltSet<
        WeeklyScheduleDayRequestModeEnum>(const <WeeklyScheduleDayRequestModeEnum>[
  _$weeklyScheduleDayRequestModeEnum_INTERVAL,
  _$weeklyScheduleDayRequestModeEnum_EXPLICIT_TIMES,
]);

Serializer<WeeklyScheduleDayRequestModeEnum>
    _$weeklyScheduleDayRequestModeEnumSerializer =
    _$WeeklyScheduleDayRequestModeEnumSerializer();

class _$WeeklyScheduleDayRequestModeEnumSerializer
    implements PrimitiveSerializer<WeeklyScheduleDayRequestModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };

  @override
  final Iterable<Type> types = const <Type>[WeeklyScheduleDayRequestModeEnum];
  @override
  final String wireName = 'WeeklyScheduleDayRequestModeEnum';

  @override
  Object serialize(
          Serializers serializers, WeeklyScheduleDayRequestModeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  WeeklyScheduleDayRequestModeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      WeeklyScheduleDayRequestModeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$WeeklyScheduleDayRequest extends WeeklyScheduleDayRequest {
  @override
  final int? dayOfWeek;
  @override
  final WeeklyScheduleDayRequestModeEnum? mode;
  @override
  final BuiltList<WorkIntervalDto>? intervals;
  @override
  final BuiltList<String>? times;
  @override
  final String? windowStart;
  @override
  final String? windowEnd;
  @override
  final bool? windowConsistent;
  @override
  final bool? modeConsistent;

  factory _$WeeklyScheduleDayRequest(
          [void Function(WeeklyScheduleDayRequestBuilder)? updates]) =>
      (WeeklyScheduleDayRequestBuilder()..update(updates))._build();

  _$WeeklyScheduleDayRequest._(
      {this.dayOfWeek,
      this.mode,
      this.intervals,
      this.times,
      this.windowStart,
      this.windowEnd,
      this.windowConsistent,
      this.modeConsistent})
      : super._();
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
        mode == other.mode &&
        intervals == other.intervals &&
        times == other.times &&
        windowStart == other.windowStart &&
        windowEnd == other.windowEnd &&
        windowConsistent == other.windowConsistent &&
        modeConsistent == other.modeConsistent;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, dayOfWeek.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jc(_$hash, times.hashCode);
    _$hash = $jc(_$hash, windowStart.hashCode);
    _$hash = $jc(_$hash, windowEnd.hashCode);
    _$hash = $jc(_$hash, windowConsistent.hashCode);
    _$hash = $jc(_$hash, modeConsistent.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WeeklyScheduleDayRequest')
          ..add('dayOfWeek', dayOfWeek)
          ..add('mode', mode)
          ..add('intervals', intervals)
          ..add('times', times)
          ..add('windowStart', windowStart)
          ..add('windowEnd', windowEnd)
          ..add('windowConsistent', windowConsistent)
          ..add('modeConsistent', modeConsistent))
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

  WeeklyScheduleDayRequestModeEnum? _mode;
  WeeklyScheduleDayRequestModeEnum? get mode => _$this._mode;
  set mode(WeeklyScheduleDayRequestModeEnum? mode) => _$this._mode = mode;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  ListBuilder<String>? _times;
  ListBuilder<String> get times => _$this._times ??= ListBuilder<String>();
  set times(ListBuilder<String>? times) => _$this._times = times;

  String? _windowStart;
  String? get windowStart => _$this._windowStart;
  set windowStart(String? windowStart) => _$this._windowStart = windowStart;

  String? _windowEnd;
  String? get windowEnd => _$this._windowEnd;
  set windowEnd(String? windowEnd) => _$this._windowEnd = windowEnd;

  bool? _windowConsistent;
  bool? get windowConsistent => _$this._windowConsistent;
  set windowConsistent(bool? windowConsistent) =>
      _$this._windowConsistent = windowConsistent;

  bool? _modeConsistent;
  bool? get modeConsistent => _$this._modeConsistent;
  set modeConsistent(bool? modeConsistent) =>
      _$this._modeConsistent = modeConsistent;

  WeeklyScheduleDayRequestBuilder() {
    WeeklyScheduleDayRequest._defaults(this);
  }

  WeeklyScheduleDayRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dayOfWeek = $v.dayOfWeek;
      _mode = $v.mode;
      _intervals = $v.intervals?.toBuilder();
      _times = $v.times?.toBuilder();
      _windowStart = $v.windowStart;
      _windowEnd = $v.windowEnd;
      _windowConsistent = $v.windowConsistent;
      _modeConsistent = $v.modeConsistent;
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
            mode: mode,
            intervals: _intervals?.build(),
            times: _times?.build(),
            windowStart: windowStart,
            windowEnd: windowEnd,
            windowConsistent: windowConsistent,
            modeConsistent: modeConsistent,
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
            r'WeeklyScheduleDayRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
