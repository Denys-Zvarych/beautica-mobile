// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'working_hours_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WorkingHoursRequest extends WorkingHoursRequest {
  @override
  final int? dayOfWeek;
  @override
  final String startTime;
  @override
  final String endTime;
  @override
  final bool? isActive;
  @override
  final bool? timeRangeValid;

  factory _$WorkingHoursRequest(
          [void Function(WorkingHoursRequestBuilder)? updates]) =>
      (WorkingHoursRequestBuilder()..update(updates))._build();

  _$WorkingHoursRequest._(
      {this.dayOfWeek,
      required this.startTime,
      required this.endTime,
      this.isActive,
      this.timeRangeValid})
      : super._();
  @override
  WorkingHoursRequest rebuild(
          void Function(WorkingHoursRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WorkingHoursRequestBuilder toBuilder() =>
      WorkingHoursRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WorkingHoursRequest &&
        dayOfWeek == other.dayOfWeek &&
        startTime == other.startTime &&
        endTime == other.endTime &&
        isActive == other.isActive &&
        timeRangeValid == other.timeRangeValid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, dayOfWeek.hashCode);
    _$hash = $jc(_$hash, startTime.hashCode);
    _$hash = $jc(_$hash, endTime.hashCode);
    _$hash = $jc(_$hash, isActive.hashCode);
    _$hash = $jc(_$hash, timeRangeValid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WorkingHoursRequest')
          ..add('dayOfWeek', dayOfWeek)
          ..add('startTime', startTime)
          ..add('endTime', endTime)
          ..add('isActive', isActive)
          ..add('timeRangeValid', timeRangeValid))
        .toString();
  }
}

class WorkingHoursRequestBuilder
    implements Builder<WorkingHoursRequest, WorkingHoursRequestBuilder> {
  _$WorkingHoursRequest? _$v;

  int? _dayOfWeek;
  int? get dayOfWeek => _$this._dayOfWeek;
  set dayOfWeek(int? dayOfWeek) => _$this._dayOfWeek = dayOfWeek;

  String? _startTime;
  String? get startTime => _$this._startTime;
  set startTime(String? startTime) => _$this._startTime = startTime;

  String? _endTime;
  String? get endTime => _$this._endTime;
  set endTime(String? endTime) => _$this._endTime = endTime;

  bool? _isActive;
  bool? get isActive => _$this._isActive;
  set isActive(bool? isActive) => _$this._isActive = isActive;

  bool? _timeRangeValid;
  bool? get timeRangeValid => _$this._timeRangeValid;
  set timeRangeValid(bool? timeRangeValid) =>
      _$this._timeRangeValid = timeRangeValid;

  WorkingHoursRequestBuilder() {
    WorkingHoursRequest._defaults(this);
  }

  WorkingHoursRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dayOfWeek = $v.dayOfWeek;
      _startTime = $v.startTime;
      _endTime = $v.endTime;
      _isActive = $v.isActive;
      _timeRangeValid = $v.timeRangeValid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WorkingHoursRequest other) {
    _$v = other as _$WorkingHoursRequest;
  }

  @override
  void update(void Function(WorkingHoursRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WorkingHoursRequest build() => _build();

  _$WorkingHoursRequest _build() {
    final _$result = _$v ??
        _$WorkingHoursRequest._(
          dayOfWeek: dayOfWeek,
          startTime: BuiltValueNullFieldError.checkNotNull(
              startTime, r'WorkingHoursRequest', 'startTime'),
          endTime: BuiltValueNullFieldError.checkNotNull(
              endTime, r'WorkingHoursRequest', 'endTime'),
          isActive: isActive,
          timeRangeValid: timeRangeValid,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
