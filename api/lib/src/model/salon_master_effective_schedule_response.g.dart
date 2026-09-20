// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_master_effective_schedule_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonMasterEffectiveScheduleResponse
    extends SalonMasterEffectiveScheduleResponse {
  @override
  final String? masterId;
  @override
  final BuiltList<EffectiveDayResponse>? days;

  factory _$SalonMasterEffectiveScheduleResponse(
          [void Function(SalonMasterEffectiveScheduleResponseBuilder)?
              updates]) =>
      (SalonMasterEffectiveScheduleResponseBuilder()..update(updates))._build();

  _$SalonMasterEffectiveScheduleResponse._({this.masterId, this.days})
      : super._();
  @override
  SalonMasterEffectiveScheduleResponse rebuild(
          void Function(SalonMasterEffectiveScheduleResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonMasterEffectiveScheduleResponseBuilder toBuilder() =>
      SalonMasterEffectiveScheduleResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonMasterEffectiveScheduleResponse &&
        masterId == other.masterId &&
        days == other.days;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, days.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonMasterEffectiveScheduleResponse')
          ..add('masterId', masterId)
          ..add('days', days))
        .toString();
  }
}

class SalonMasterEffectiveScheduleResponseBuilder
    implements
        Builder<SalonMasterEffectiveScheduleResponse,
            SalonMasterEffectiveScheduleResponseBuilder> {
  _$SalonMasterEffectiveScheduleResponse? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  ListBuilder<EffectiveDayResponse>? _days;
  ListBuilder<EffectiveDayResponse> get days =>
      _$this._days ??= ListBuilder<EffectiveDayResponse>();
  set days(ListBuilder<EffectiveDayResponse>? days) => _$this._days = days;

  SalonMasterEffectiveScheduleResponseBuilder() {
    SalonMasterEffectiveScheduleResponse._defaults(this);
  }

  SalonMasterEffectiveScheduleResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _days = $v.days?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonMasterEffectiveScheduleResponse other) {
    _$v = other as _$SalonMasterEffectiveScheduleResponse;
  }

  @override
  void update(
      void Function(SalonMasterEffectiveScheduleResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonMasterEffectiveScheduleResponse build() => _build();

  _$SalonMasterEffectiveScheduleResponse _build() {
    _$SalonMasterEffectiveScheduleResponse _$result;
    try {
      _$result = _$v ??
          _$SalonMasterEffectiveScheduleResponse._(
            masterId: masterId,
            days: _days?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'days';
        _days?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonMasterEffectiveScheduleResponse',
            _$failedField,
            e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
