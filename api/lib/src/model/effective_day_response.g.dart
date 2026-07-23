// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'effective_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EffectiveDayResponseSource_Enum
    _$effectiveDayResponseSourceEnum_TEMPLATE =
    const EffectiveDayResponseSource_Enum._('TEMPLATE');
const EffectiveDayResponseSource_Enum
    _$effectiveDayResponseSourceEnum_OVERRIDE_CUSTOM =
    const EffectiveDayResponseSource_Enum._('OVERRIDE_CUSTOM');
const EffectiveDayResponseSource_Enum
    _$effectiveDayResponseSourceEnum_OVERRIDE_DAY_OFF =
    const EffectiveDayResponseSource_Enum._('OVERRIDE_DAY_OFF');
const EffectiveDayResponseSource_Enum
    _$effectiveDayResponseSourceEnum_NO_SCHEDULE =
    const EffectiveDayResponseSource_Enum._('NO_SCHEDULE');

EffectiveDayResponseSource_Enum _$effectiveDayResponseSourceEnumValueOf(
    String name) {
  switch (name) {
    case 'TEMPLATE':
      return _$effectiveDayResponseSourceEnum_TEMPLATE;
    case 'OVERRIDE_CUSTOM':
      return _$effectiveDayResponseSourceEnum_OVERRIDE_CUSTOM;
    case 'OVERRIDE_DAY_OFF':
      return _$effectiveDayResponseSourceEnum_OVERRIDE_DAY_OFF;
    case 'NO_SCHEDULE':
      return _$effectiveDayResponseSourceEnum_NO_SCHEDULE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<EffectiveDayResponseSource_Enum>
    _$effectiveDayResponseSourceEnumValues = BuiltSet<
        EffectiveDayResponseSource_Enum>(const <EffectiveDayResponseSource_Enum>[
  _$effectiveDayResponseSourceEnum_TEMPLATE,
  _$effectiveDayResponseSourceEnum_OVERRIDE_CUSTOM,
  _$effectiveDayResponseSourceEnum_OVERRIDE_DAY_OFF,
  _$effectiveDayResponseSourceEnum_NO_SCHEDULE,
]);

Serializer<EffectiveDayResponseSource_Enum>
    _$effectiveDayResponseSourceEnumSerializer =
    _$EffectiveDayResponseSource_EnumSerializer();

class _$EffectiveDayResponseSource_EnumSerializer
    implements PrimitiveSerializer<EffectiveDayResponseSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'TEMPLATE': 'TEMPLATE',
    'OVERRIDE_CUSTOM': 'OVERRIDE_CUSTOM',
    'OVERRIDE_DAY_OFF': 'OVERRIDE_DAY_OFF',
    'NO_SCHEDULE': 'NO_SCHEDULE',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'TEMPLATE': 'TEMPLATE',
    'OVERRIDE_CUSTOM': 'OVERRIDE_CUSTOM',
    'OVERRIDE_DAY_OFF': 'OVERRIDE_DAY_OFF',
    'NO_SCHEDULE': 'NO_SCHEDULE',
  };

  @override
  final Iterable<Type> types = const <Type>[EffectiveDayResponseSource_Enum];
  @override
  final String wireName = 'EffectiveDayResponseSource_Enum';

  @override
  Object serialize(
          Serializers serializers, EffectiveDayResponseSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  EffectiveDayResponseSource_Enum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      EffectiveDayResponseSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$EffectiveDayResponse extends EffectiveDayResponse {
  @override
  final Date? date;
  @override
  final EffectiveDayResponseSource_Enum? source_;
  @override
  final BuiltList<WorkIntervalDto>? intervals;
  @override
  final BuiltList<String>? times;

  factory _$EffectiveDayResponse(
          [void Function(EffectiveDayResponseBuilder)? updates]) =>
      (EffectiveDayResponseBuilder()..update(updates))._build();

  _$EffectiveDayResponse._(
      {this.date, this.source_, this.intervals, this.times})
      : super._();
  @override
  EffectiveDayResponse rebuild(
          void Function(EffectiveDayResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EffectiveDayResponseBuilder toBuilder() =>
      EffectiveDayResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EffectiveDayResponse &&
        date == other.date &&
        source_ == other.source_ &&
        intervals == other.intervals &&
        times == other.times;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jc(_$hash, times.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EffectiveDayResponse')
          ..add('date', date)
          ..add('source_', source_)
          ..add('intervals', intervals)
          ..add('times', times))
        .toString();
  }
}

class EffectiveDayResponseBuilder
    implements Builder<EffectiveDayResponse, EffectiveDayResponseBuilder> {
  _$EffectiveDayResponse? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  EffectiveDayResponseSource_Enum? _source_;
  EffectiveDayResponseSource_Enum? get source_ => _$this._source_;
  set source_(EffectiveDayResponseSource_Enum? source_) =>
      _$this._source_ = source_;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  ListBuilder<String>? _times;
  ListBuilder<String> get times => _$this._times ??= ListBuilder<String>();
  set times(ListBuilder<String>? times) => _$this._times = times;

  EffectiveDayResponseBuilder() {
    EffectiveDayResponse._defaults(this);
  }

  EffectiveDayResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _source_ = $v.source_;
      _intervals = $v.intervals?.toBuilder();
      _times = $v.times?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EffectiveDayResponse other) {
    _$v = other as _$EffectiveDayResponse;
  }

  @override
  void update(void Function(EffectiveDayResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EffectiveDayResponse build() => _build();

  _$EffectiveDayResponse _build() {
    _$EffectiveDayResponse _$result;
    try {
      _$result = _$v ??
          _$EffectiveDayResponse._(
            date: date,
            source_: source_,
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
            r'EffectiveDayResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
