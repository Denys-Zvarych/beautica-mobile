// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'working_hours_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WorkingHoursResponse extends WorkingHoursResponse {
  @override
  final String? id;
  @override
  final int? dayOfWeek;
  @override
  final String? startTime;
  @override
  final String? endTime;
  @override
  final bool? isActive;

  factory _$WorkingHoursResponse(
          [void Function(WorkingHoursResponseBuilder)? updates]) =>
      (WorkingHoursResponseBuilder()..update(updates))._build();

  _$WorkingHoursResponse._(
      {this.id, this.dayOfWeek, this.startTime, this.endTime, this.isActive})
      : super._();
  @override
  WorkingHoursResponse rebuild(
          void Function(WorkingHoursResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WorkingHoursResponseBuilder toBuilder() =>
      WorkingHoursResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WorkingHoursResponse &&
        id == other.id &&
        dayOfWeek == other.dayOfWeek &&
        startTime == other.startTime &&
        endTime == other.endTime &&
        isActive == other.isActive;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, dayOfWeek.hashCode);
    _$hash = $jc(_$hash, startTime.hashCode);
    _$hash = $jc(_$hash, endTime.hashCode);
    _$hash = $jc(_$hash, isActive.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WorkingHoursResponse')
          ..add('id', id)
          ..add('dayOfWeek', dayOfWeek)
          ..add('startTime', startTime)
          ..add('endTime', endTime)
          ..add('isActive', isActive))
        .toString();
  }
}

class WorkingHoursResponseBuilder
    implements Builder<WorkingHoursResponse, WorkingHoursResponseBuilder> {
  _$WorkingHoursResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

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

  WorkingHoursResponseBuilder() {
    WorkingHoursResponse._defaults(this);
  }

  WorkingHoursResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _dayOfWeek = $v.dayOfWeek;
      _startTime = $v.startTime;
      _endTime = $v.endTime;
      _isActive = $v.isActive;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WorkingHoursResponse other) {
    _$v = other as _$WorkingHoursResponse;
  }

  @override
  void update(void Function(WorkingHoursResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WorkingHoursResponse build() => _build();

  _$WorkingHoursResponse _build() {
    final _$result = _$v ??
        _$WorkingHoursResponse._(
          id: id,
          dayOfWeek: dayOfWeek,
          startTime: startTime,
          endTime: endTime,
          isActive: isActive,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
