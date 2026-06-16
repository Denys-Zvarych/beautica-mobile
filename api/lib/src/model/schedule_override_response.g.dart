// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_override_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ScheduleOverrideResponseKindEnum
    _$scheduleOverrideResponseKindEnum_DAY_OFF =
    const ScheduleOverrideResponseKindEnum._('DAY_OFF');
const ScheduleOverrideResponseKindEnum
    _$scheduleOverrideResponseKindEnum_CUSTOM_HOURS =
    const ScheduleOverrideResponseKindEnum._('CUSTOM_HOURS');

ScheduleOverrideResponseKindEnum _$scheduleOverrideResponseKindEnumValueOf(
    String name) {
  switch (name) {
    case 'DAY_OFF':
      return _$scheduleOverrideResponseKindEnum_DAY_OFF;
    case 'CUSTOM_HOURS':
      return _$scheduleOverrideResponseKindEnum_CUSTOM_HOURS;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ScheduleOverrideResponseKindEnum>
    _$scheduleOverrideResponseKindEnumValues = BuiltSet<
        ScheduleOverrideResponseKindEnum>(const <ScheduleOverrideResponseKindEnum>[
  _$scheduleOverrideResponseKindEnum_DAY_OFF,
  _$scheduleOverrideResponseKindEnum_CUSTOM_HOURS,
]);

const ScheduleOverrideResponseModeEnum
    _$scheduleOverrideResponseModeEnum_INTERVAL =
    const ScheduleOverrideResponseModeEnum._('INTERVAL');
const ScheduleOverrideResponseModeEnum
    _$scheduleOverrideResponseModeEnum_EXPLICIT_TIMES =
    const ScheduleOverrideResponseModeEnum._('EXPLICIT_TIMES');

ScheduleOverrideResponseModeEnum _$scheduleOverrideResponseModeEnumValueOf(
    String name) {
  switch (name) {
    case 'INTERVAL':
      return _$scheduleOverrideResponseModeEnum_INTERVAL;
    case 'EXPLICIT_TIMES':
      return _$scheduleOverrideResponseModeEnum_EXPLICIT_TIMES;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ScheduleOverrideResponseModeEnum>
    _$scheduleOverrideResponseModeEnumValues = BuiltSet<
        ScheduleOverrideResponseModeEnum>(const <ScheduleOverrideResponseModeEnum>[
  _$scheduleOverrideResponseModeEnum_INTERVAL,
  _$scheduleOverrideResponseModeEnum_EXPLICIT_TIMES,
]);

Serializer<ScheduleOverrideResponseKindEnum>
    _$scheduleOverrideResponseKindEnumSerializer =
    _$ScheduleOverrideResponseKindEnumSerializer();
Serializer<ScheduleOverrideResponseModeEnum>
    _$scheduleOverrideResponseModeEnumSerializer =
    _$ScheduleOverrideResponseModeEnumSerializer();

class _$ScheduleOverrideResponseKindEnumSerializer
    implements PrimitiveSerializer<ScheduleOverrideResponseKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'DAY_OFF': 'DAY_OFF',
    'CUSTOM_HOURS': 'CUSTOM_HOURS',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'DAY_OFF': 'DAY_OFF',
    'CUSTOM_HOURS': 'CUSTOM_HOURS',
  };

  @override
  final Iterable<Type> types = const <Type>[ScheduleOverrideResponseKindEnum];
  @override
  final String wireName = 'ScheduleOverrideResponseKindEnum';

  @override
  Object serialize(
          Serializers serializers, ScheduleOverrideResponseKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ScheduleOverrideResponseKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ScheduleOverrideResponseKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ScheduleOverrideResponseModeEnumSerializer
    implements PrimitiveSerializer<ScheduleOverrideResponseModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };

  @override
  final Iterable<Type> types = const <Type>[ScheduleOverrideResponseModeEnum];
  @override
  final String wireName = 'ScheduleOverrideResponseModeEnum';

  @override
  Object serialize(
          Serializers serializers, ScheduleOverrideResponseModeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ScheduleOverrideResponseModeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ScheduleOverrideResponseModeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ScheduleOverrideResponse extends ScheduleOverrideResponse {
  @override
  final Date? date;
  @override
  final ScheduleOverrideResponseKindEnum? kind;
  @override
  final ScheduleOverrideResponseModeEnum? mode;
  @override
  final BuiltList<WorkIntervalDto>? intervals;
  @override
  final BuiltList<String>? times;

  factory _$ScheduleOverrideResponse(
          [void Function(ScheduleOverrideResponseBuilder)? updates]) =>
      (ScheduleOverrideResponseBuilder()..update(updates))._build();

  _$ScheduleOverrideResponse._(
      {this.date, this.kind, this.mode, this.intervals, this.times})
      : super._();
  @override
  ScheduleOverrideResponse rebuild(
          void Function(ScheduleOverrideResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleOverrideResponseBuilder toBuilder() =>
      ScheduleOverrideResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScheduleOverrideResponse &&
        date == other.date &&
        kind == other.kind &&
        mode == other.mode &&
        intervals == other.intervals &&
        times == other.times;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jc(_$hash, times.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScheduleOverrideResponse')
          ..add('date', date)
          ..add('kind', kind)
          ..add('mode', mode)
          ..add('intervals', intervals)
          ..add('times', times))
        .toString();
  }
}

class ScheduleOverrideResponseBuilder
    implements
        Builder<ScheduleOverrideResponse, ScheduleOverrideResponseBuilder> {
  _$ScheduleOverrideResponse? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  ScheduleOverrideResponseKindEnum? _kind;
  ScheduleOverrideResponseKindEnum? get kind => _$this._kind;
  set kind(ScheduleOverrideResponseKindEnum? kind) => _$this._kind = kind;

  ScheduleOverrideResponseModeEnum? _mode;
  ScheduleOverrideResponseModeEnum? get mode => _$this._mode;
  set mode(ScheduleOverrideResponseModeEnum? mode) => _$this._mode = mode;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  ListBuilder<String>? _times;
  ListBuilder<String> get times => _$this._times ??= ListBuilder<String>();
  set times(ListBuilder<String>? times) => _$this._times = times;

  ScheduleOverrideResponseBuilder() {
    ScheduleOverrideResponse._defaults(this);
  }

  ScheduleOverrideResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _kind = $v.kind;
      _mode = $v.mode;
      _intervals = $v.intervals?.toBuilder();
      _times = $v.times?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScheduleOverrideResponse other) {
    _$v = other as _$ScheduleOverrideResponse;
  }

  @override
  void update(void Function(ScheduleOverrideResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScheduleOverrideResponse build() => _build();

  _$ScheduleOverrideResponse _build() {
    _$ScheduleOverrideResponse _$result;
    try {
      _$result = _$v ??
          _$ScheduleOverrideResponse._(
            date: date,
            kind: kind,
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
            r'ScheduleOverrideResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
