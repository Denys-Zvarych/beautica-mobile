// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_override_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ScheduleOverrideRequestKindEnum
    _$scheduleOverrideRequestKindEnum_DAY_OFF =
    const ScheduleOverrideRequestKindEnum._('DAY_OFF');
const ScheduleOverrideRequestKindEnum
    _$scheduleOverrideRequestKindEnum_CUSTOM_HOURS =
    const ScheduleOverrideRequestKindEnum._('CUSTOM_HOURS');

ScheduleOverrideRequestKindEnum _$scheduleOverrideRequestKindEnumValueOf(
    String name) {
  switch (name) {
    case 'DAY_OFF':
      return _$scheduleOverrideRequestKindEnum_DAY_OFF;
    case 'CUSTOM_HOURS':
      return _$scheduleOverrideRequestKindEnum_CUSTOM_HOURS;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ScheduleOverrideRequestKindEnum>
    _$scheduleOverrideRequestKindEnumValues = BuiltSet<
        ScheduleOverrideRequestKindEnum>(const <ScheduleOverrideRequestKindEnum>[
  _$scheduleOverrideRequestKindEnum_DAY_OFF,
  _$scheduleOverrideRequestKindEnum_CUSTOM_HOURS,
]);

const ScheduleOverrideRequestModeEnum
    _$scheduleOverrideRequestModeEnum_INTERVAL =
    const ScheduleOverrideRequestModeEnum._('INTERVAL');
const ScheduleOverrideRequestModeEnum
    _$scheduleOverrideRequestModeEnum_EXPLICIT_TIMES =
    const ScheduleOverrideRequestModeEnum._('EXPLICIT_TIMES');

ScheduleOverrideRequestModeEnum _$scheduleOverrideRequestModeEnumValueOf(
    String name) {
  switch (name) {
    case 'INTERVAL':
      return _$scheduleOverrideRequestModeEnum_INTERVAL;
    case 'EXPLICIT_TIMES':
      return _$scheduleOverrideRequestModeEnum_EXPLICIT_TIMES;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ScheduleOverrideRequestModeEnum>
    _$scheduleOverrideRequestModeEnumValues = BuiltSet<
        ScheduleOverrideRequestModeEnum>(const <ScheduleOverrideRequestModeEnum>[
  _$scheduleOverrideRequestModeEnum_INTERVAL,
  _$scheduleOverrideRequestModeEnum_EXPLICIT_TIMES,
]);

Serializer<ScheduleOverrideRequestKindEnum>
    _$scheduleOverrideRequestKindEnumSerializer =
    _$ScheduleOverrideRequestKindEnumSerializer();
Serializer<ScheduleOverrideRequestModeEnum>
    _$scheduleOverrideRequestModeEnumSerializer =
    _$ScheduleOverrideRequestModeEnumSerializer();

class _$ScheduleOverrideRequestKindEnumSerializer
    implements PrimitiveSerializer<ScheduleOverrideRequestKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'DAY_OFF': 'DAY_OFF',
    'CUSTOM_HOURS': 'CUSTOM_HOURS',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'DAY_OFF': 'DAY_OFF',
    'CUSTOM_HOURS': 'CUSTOM_HOURS',
  };

  @override
  final Iterable<Type> types = const <Type>[ScheduleOverrideRequestKindEnum];
  @override
  final String wireName = 'ScheduleOverrideRequestKindEnum';

  @override
  Object serialize(
          Serializers serializers, ScheduleOverrideRequestKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ScheduleOverrideRequestKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ScheduleOverrideRequestKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ScheduleOverrideRequestModeEnumSerializer
    implements PrimitiveSerializer<ScheduleOverrideRequestModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'INTERVAL': 'INTERVAL',
    'EXPLICIT_TIMES': 'EXPLICIT_TIMES',
  };

  @override
  final Iterable<Type> types = const <Type>[ScheduleOverrideRequestModeEnum];
  @override
  final String wireName = 'ScheduleOverrideRequestModeEnum';

  @override
  Object serialize(
          Serializers serializers, ScheduleOverrideRequestModeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ScheduleOverrideRequestModeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ScheduleOverrideRequestModeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ScheduleOverrideRequest extends ScheduleOverrideRequest {
  @override
  final Date date;
  @override
  final ScheduleOverrideRequestKindEnum kind;
  @override
  final ScheduleOverrideRequestModeEnum? mode;
  @override
  final BuiltList<WorkIntervalDto>? intervals;
  @override
  final BuiltList<String>? times;
  @override
  final bool? cancelOverlapping;
  @override
  final bool? kindConsistent;

  factory _$ScheduleOverrideRequest(
          [void Function(ScheduleOverrideRequestBuilder)? updates]) =>
      (ScheduleOverrideRequestBuilder()..update(updates))._build();

  _$ScheduleOverrideRequest._(
      {required this.date,
      required this.kind,
      this.mode,
      this.intervals,
      this.times,
      this.cancelOverlapping,
      this.kindConsistent})
      : super._();
  @override
  ScheduleOverrideRequest rebuild(
          void Function(ScheduleOverrideRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleOverrideRequestBuilder toBuilder() =>
      ScheduleOverrideRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScheduleOverrideRequest &&
        date == other.date &&
        kind == other.kind &&
        mode == other.mode &&
        intervals == other.intervals &&
        times == other.times &&
        cancelOverlapping == other.cancelOverlapping &&
        kindConsistent == other.kindConsistent;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jc(_$hash, times.hashCode);
    _$hash = $jc(_$hash, cancelOverlapping.hashCode);
    _$hash = $jc(_$hash, kindConsistent.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScheduleOverrideRequest')
          ..add('date', date)
          ..add('kind', kind)
          ..add('mode', mode)
          ..add('intervals', intervals)
          ..add('times', times)
          ..add('cancelOverlapping', cancelOverlapping)
          ..add('kindConsistent', kindConsistent))
        .toString();
  }
}

class ScheduleOverrideRequestBuilder
    implements
        Builder<ScheduleOverrideRequest, ScheduleOverrideRequestBuilder> {
  _$ScheduleOverrideRequest? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  ScheduleOverrideRequestKindEnum? _kind;
  ScheduleOverrideRequestKindEnum? get kind => _$this._kind;
  set kind(ScheduleOverrideRequestKindEnum? kind) => _$this._kind = kind;

  ScheduleOverrideRequestModeEnum? _mode;
  ScheduleOverrideRequestModeEnum? get mode => _$this._mode;
  set mode(ScheduleOverrideRequestModeEnum? mode) => _$this._mode = mode;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  ListBuilder<String>? _times;
  ListBuilder<String> get times => _$this._times ??= ListBuilder<String>();
  set times(ListBuilder<String>? times) => _$this._times = times;

  bool? _cancelOverlapping;
  bool? get cancelOverlapping => _$this._cancelOverlapping;
  set cancelOverlapping(bool? cancelOverlapping) =>
      _$this._cancelOverlapping = cancelOverlapping;

  bool? _kindConsistent;
  bool? get kindConsistent => _$this._kindConsistent;
  set kindConsistent(bool? kindConsistent) =>
      _$this._kindConsistent = kindConsistent;

  ScheduleOverrideRequestBuilder() {
    ScheduleOverrideRequest._defaults(this);
  }

  ScheduleOverrideRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _kind = $v.kind;
      _mode = $v.mode;
      _intervals = $v.intervals?.toBuilder();
      _times = $v.times?.toBuilder();
      _cancelOverlapping = $v.cancelOverlapping;
      _kindConsistent = $v.kindConsistent;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScheduleOverrideRequest other) {
    _$v = other as _$ScheduleOverrideRequest;
  }

  @override
  void update(void Function(ScheduleOverrideRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScheduleOverrideRequest build() => _build();

  _$ScheduleOverrideRequest _build() {
    _$ScheduleOverrideRequest _$result;
    try {
      _$result = _$v ??
          _$ScheduleOverrideRequest._(
            date: BuiltValueNullFieldError.checkNotNull(
                date, r'ScheduleOverrideRequest', 'date'),
            kind: BuiltValueNullFieldError.checkNotNull(
                kind, r'ScheduleOverrideRequest', 'kind'),
            mode: mode,
            intervals: _intervals?.build(),
            times: _times?.build(),
            cancelOverlapping: cancelOverlapping,
            kindConsistent: kindConsistent,
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
            r'ScheduleOverrideRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
