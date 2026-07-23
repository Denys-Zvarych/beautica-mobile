// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_working_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MasterWorkingDayResponse extends MasterWorkingDayResponse {
  @override
  final Date? date;
  @override
  final bool? working;

  factory _$MasterWorkingDayResponse(
          [void Function(MasterWorkingDayResponseBuilder)? updates]) =>
      (MasterWorkingDayResponseBuilder()..update(updates))._build();

  _$MasterWorkingDayResponse._({this.date, this.working}) : super._();
  @override
  MasterWorkingDayResponse rebuild(
          void Function(MasterWorkingDayResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterWorkingDayResponseBuilder toBuilder() =>
      MasterWorkingDayResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterWorkingDayResponse &&
        date == other.date &&
        working == other.working;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, working.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterWorkingDayResponse')
          ..add('date', date)
          ..add('working', working))
        .toString();
  }
}

class MasterWorkingDayResponseBuilder
    implements
        Builder<MasterWorkingDayResponse, MasterWorkingDayResponseBuilder> {
  _$MasterWorkingDayResponse? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  bool? _working;
  bool? get working => _$this._working;
  set working(bool? working) => _$this._working = working;

  MasterWorkingDayResponseBuilder() {
    MasterWorkingDayResponse._defaults(this);
  }

  MasterWorkingDayResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _working = $v.working;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MasterWorkingDayResponse other) {
    _$v = other as _$MasterWorkingDayResponse;
  }

  @override
  void update(void Function(MasterWorkingDayResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterWorkingDayResponse build() => _build();

  _$MasterWorkingDayResponse _build() {
    final _$result = _$v ??
        _$MasterWorkingDayResponse._(
          date: date,
          working: working,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
