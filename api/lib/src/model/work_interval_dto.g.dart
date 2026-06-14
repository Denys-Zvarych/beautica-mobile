// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work_interval_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WorkIntervalDto extends WorkIntervalDto {
  @override
  final String startTime;
  @override
  final String endTime;
  @override
  final bool? ordered;

  factory _$WorkIntervalDto([void Function(WorkIntervalDtoBuilder)? updates]) =>
      (WorkIntervalDtoBuilder()..update(updates))._build();

  _$WorkIntervalDto._(
      {required this.startTime, required this.endTime, this.ordered})
      : super._();
  @override
  WorkIntervalDto rebuild(void Function(WorkIntervalDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WorkIntervalDtoBuilder toBuilder() => WorkIntervalDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WorkIntervalDto &&
        startTime == other.startTime &&
        endTime == other.endTime &&
        ordered == other.ordered;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startTime.hashCode);
    _$hash = $jc(_$hash, endTime.hashCode);
    _$hash = $jc(_$hash, ordered.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WorkIntervalDto')
          ..add('startTime', startTime)
          ..add('endTime', endTime)
          ..add('ordered', ordered))
        .toString();
  }
}

class WorkIntervalDtoBuilder
    implements Builder<WorkIntervalDto, WorkIntervalDtoBuilder> {
  _$WorkIntervalDto? _$v;

  String? _startTime;
  String? get startTime => _$this._startTime;
  set startTime(String? startTime) => _$this._startTime = startTime;

  String? _endTime;
  String? get endTime => _$this._endTime;
  set endTime(String? endTime) => _$this._endTime = endTime;

  bool? _ordered;
  bool? get ordered => _$this._ordered;
  set ordered(bool? ordered) => _$this._ordered = ordered;

  WorkIntervalDtoBuilder() {
    WorkIntervalDto._defaults(this);
  }

  WorkIntervalDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startTime = $v.startTime;
      _endTime = $v.endTime;
      _ordered = $v.ordered;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WorkIntervalDto other) {
    _$v = other as _$WorkIntervalDto;
  }

  @override
  void update(void Function(WorkIntervalDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WorkIntervalDto build() => _build();

  _$WorkIntervalDto _build() {
    final _$result = _$v ??
        _$WorkIntervalDto._(
          startTime: BuiltValueNullFieldError.checkNotNull(
              startTime, r'WorkIntervalDto', 'startTime'),
          endTime: BuiltValueNullFieldError.checkNotNull(
              endTime, r'WorkIntervalDto', 'endTime'),
          ordered: ordered,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
