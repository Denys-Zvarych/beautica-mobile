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

const ScheduleOverrideResponseReasonEnum
    _$scheduleOverrideResponseReasonEnum_VACATION =
    const ScheduleOverrideResponseReasonEnum._('VACATION');
const ScheduleOverrideResponseReasonEnum
    _$scheduleOverrideResponseReasonEnum_HOLIDAY =
    const ScheduleOverrideResponseReasonEnum._('HOLIDAY');
const ScheduleOverrideResponseReasonEnum
    _$scheduleOverrideResponseReasonEnum_SICK_DAY =
    const ScheduleOverrideResponseReasonEnum._('SICK_DAY');
const ScheduleOverrideResponseReasonEnum
    _$scheduleOverrideResponseReasonEnum_OTHER =
    const ScheduleOverrideResponseReasonEnum._('OTHER');

ScheduleOverrideResponseReasonEnum _$scheduleOverrideResponseReasonEnumValueOf(
    String name) {
  switch (name) {
    case 'VACATION':
      return _$scheduleOverrideResponseReasonEnum_VACATION;
    case 'HOLIDAY':
      return _$scheduleOverrideResponseReasonEnum_HOLIDAY;
    case 'SICK_DAY':
      return _$scheduleOverrideResponseReasonEnum_SICK_DAY;
    case 'OTHER':
      return _$scheduleOverrideResponseReasonEnum_OTHER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ScheduleOverrideResponseReasonEnum>
    _$scheduleOverrideResponseReasonEnumValues = BuiltSet<
        ScheduleOverrideResponseReasonEnum>(const <ScheduleOverrideResponseReasonEnum>[
  _$scheduleOverrideResponseReasonEnum_VACATION,
  _$scheduleOverrideResponseReasonEnum_HOLIDAY,
  _$scheduleOverrideResponseReasonEnum_SICK_DAY,
  _$scheduleOverrideResponseReasonEnum_OTHER,
]);

Serializer<ScheduleOverrideResponseKindEnum>
    _$scheduleOverrideResponseKindEnumSerializer =
    _$ScheduleOverrideResponseKindEnumSerializer();
Serializer<ScheduleOverrideResponseReasonEnum>
    _$scheduleOverrideResponseReasonEnumSerializer =
    _$ScheduleOverrideResponseReasonEnumSerializer();

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

class _$ScheduleOverrideResponseReasonEnumSerializer
    implements PrimitiveSerializer<ScheduleOverrideResponseReasonEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'VACATION': 'VACATION',
    'HOLIDAY': 'HOLIDAY',
    'SICK_DAY': 'SICK_DAY',
    'OTHER': 'OTHER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'VACATION': 'VACATION',
    'HOLIDAY': 'HOLIDAY',
    'SICK_DAY': 'SICK_DAY',
    'OTHER': 'OTHER',
  };

  @override
  final Iterable<Type> types = const <Type>[ScheduleOverrideResponseReasonEnum];
  @override
  final String wireName = 'ScheduleOverrideResponseReasonEnum';

  @override
  Object serialize(
          Serializers serializers, ScheduleOverrideResponseReasonEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ScheduleOverrideResponseReasonEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ScheduleOverrideResponseReasonEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ScheduleOverrideResponse extends ScheduleOverrideResponse {
  @override
  final Date? date;
  @override
  final ScheduleOverrideResponseKindEnum? kind;
  @override
  final ScheduleOverrideResponseReasonEnum? reason;
  @override
  final String? note;
  @override
  final BuiltList<WorkIntervalDto>? intervals;

  factory _$ScheduleOverrideResponse(
          [void Function(ScheduleOverrideResponseBuilder)? updates]) =>
      (ScheduleOverrideResponseBuilder()..update(updates))._build();

  _$ScheduleOverrideResponse._(
      {this.date, this.kind, this.reason, this.note, this.intervals})
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
        reason == other.reason &&
        note == other.note &&
        intervals == other.intervals;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, intervals.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScheduleOverrideResponse')
          ..add('date', date)
          ..add('kind', kind)
          ..add('reason', reason)
          ..add('note', note)
          ..add('intervals', intervals))
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

  ScheduleOverrideResponseReasonEnum? _reason;
  ScheduleOverrideResponseReasonEnum? get reason => _$this._reason;
  set reason(ScheduleOverrideResponseReasonEnum? reason) =>
      _$this._reason = reason;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  ListBuilder<WorkIntervalDto>? _intervals;
  ListBuilder<WorkIntervalDto> get intervals =>
      _$this._intervals ??= ListBuilder<WorkIntervalDto>();
  set intervals(ListBuilder<WorkIntervalDto>? intervals) =>
      _$this._intervals = intervals;

  ScheduleOverrideResponseBuilder() {
    ScheduleOverrideResponse._defaults(this);
  }

  ScheduleOverrideResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _kind = $v.kind;
      _reason = $v.reason;
      _note = $v.note;
      _intervals = $v.intervals?.toBuilder();
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
            reason: reason,
            note: note,
            intervals: _intervals?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'intervals';
        _intervals?.build();
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
