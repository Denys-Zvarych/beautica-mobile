// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_exception_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ScheduleExceptionRequestReasonEnum
    _$scheduleExceptionRequestReasonEnum_VACATION =
    const ScheduleExceptionRequestReasonEnum._('VACATION');
const ScheduleExceptionRequestReasonEnum
    _$scheduleExceptionRequestReasonEnum_HOLIDAY =
    const ScheduleExceptionRequestReasonEnum._('HOLIDAY');
const ScheduleExceptionRequestReasonEnum
    _$scheduleExceptionRequestReasonEnum_SICK_DAY =
    const ScheduleExceptionRequestReasonEnum._('SICK_DAY');
const ScheduleExceptionRequestReasonEnum
    _$scheduleExceptionRequestReasonEnum_OTHER =
    const ScheduleExceptionRequestReasonEnum._('OTHER');

ScheduleExceptionRequestReasonEnum _$scheduleExceptionRequestReasonEnumValueOf(
    String name) {
  switch (name) {
    case 'VACATION':
      return _$scheduleExceptionRequestReasonEnum_VACATION;
    case 'HOLIDAY':
      return _$scheduleExceptionRequestReasonEnum_HOLIDAY;
    case 'SICK_DAY':
      return _$scheduleExceptionRequestReasonEnum_SICK_DAY;
    case 'OTHER':
      return _$scheduleExceptionRequestReasonEnum_OTHER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ScheduleExceptionRequestReasonEnum>
    _$scheduleExceptionRequestReasonEnumValues = BuiltSet<
        ScheduleExceptionRequestReasonEnum>(const <ScheduleExceptionRequestReasonEnum>[
  _$scheduleExceptionRequestReasonEnum_VACATION,
  _$scheduleExceptionRequestReasonEnum_HOLIDAY,
  _$scheduleExceptionRequestReasonEnum_SICK_DAY,
  _$scheduleExceptionRequestReasonEnum_OTHER,
]);

Serializer<ScheduleExceptionRequestReasonEnum>
    _$scheduleExceptionRequestReasonEnumSerializer =
    _$ScheduleExceptionRequestReasonEnumSerializer();

class _$ScheduleExceptionRequestReasonEnumSerializer
    implements PrimitiveSerializer<ScheduleExceptionRequestReasonEnum> {
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
  final Iterable<Type> types = const <Type>[ScheduleExceptionRequestReasonEnum];
  @override
  final String wireName = 'ScheduleExceptionRequestReasonEnum';

  @override
  Object serialize(
          Serializers serializers, ScheduleExceptionRequestReasonEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ScheduleExceptionRequestReasonEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ScheduleExceptionRequestReasonEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ScheduleExceptionRequest extends ScheduleExceptionRequest {
  @override
  final Date date;
  @override
  final ScheduleExceptionRequestReasonEnum reason;
  @override
  final String? note;

  factory _$ScheduleExceptionRequest(
          [void Function(ScheduleExceptionRequestBuilder)? updates]) =>
      (ScheduleExceptionRequestBuilder()..update(updates))._build();

  _$ScheduleExceptionRequest._(
      {required this.date, required this.reason, this.note})
      : super._();
  @override
  ScheduleExceptionRequest rebuild(
          void Function(ScheduleExceptionRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScheduleExceptionRequestBuilder toBuilder() =>
      ScheduleExceptionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScheduleExceptionRequest &&
        date == other.date &&
        reason == other.reason &&
        note == other.note;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScheduleExceptionRequest')
          ..add('date', date)
          ..add('reason', reason)
          ..add('note', note))
        .toString();
  }
}

class ScheduleExceptionRequestBuilder
    implements
        Builder<ScheduleExceptionRequest, ScheduleExceptionRequestBuilder> {
  _$ScheduleExceptionRequest? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  ScheduleExceptionRequestReasonEnum? _reason;
  ScheduleExceptionRequestReasonEnum? get reason => _$this._reason;
  set reason(ScheduleExceptionRequestReasonEnum? reason) =>
      _$this._reason = reason;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  ScheduleExceptionRequestBuilder() {
    ScheduleExceptionRequest._defaults(this);
  }

  ScheduleExceptionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _reason = $v.reason;
      _note = $v.note;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScheduleExceptionRequest other) {
    _$v = other as _$ScheduleExceptionRequest;
  }

  @override
  void update(void Function(ScheduleExceptionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScheduleExceptionRequest build() => _build();

  _$ScheduleExceptionRequest _build() {
    final _$result = _$v ??
        _$ScheduleExceptionRequest._(
          date: BuiltValueNullFieldError.checkNotNull(
              date, r'ScheduleExceptionRequest', 'date'),
          reason: BuiltValueNullFieldError.checkNotNull(
              reason, r'ScheduleExceptionRequest', 'reason'),
          note: note,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
