// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_service_master_ref.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonServiceMasterRef extends SalonServiceMasterRef {
  @override
  final String masterId;
  @override
  final String masterServiceId;

  factory _$SalonServiceMasterRef(
          [void Function(SalonServiceMasterRefBuilder)? updates]) =>
      (SalonServiceMasterRefBuilder()..update(updates))._build();

  _$SalonServiceMasterRef._(
      {required this.masterId, required this.masterServiceId})
      : super._();
  @override
  SalonServiceMasterRef rebuild(
          void Function(SalonServiceMasterRefBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonServiceMasterRefBuilder toBuilder() =>
      SalonServiceMasterRefBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonServiceMasterRef &&
        masterId == other.masterId &&
        masterServiceId == other.masterServiceId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterServiceId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonServiceMasterRef')
          ..add('masterId', masterId)
          ..add('masterServiceId', masterServiceId))
        .toString();
  }
}

class SalonServiceMasterRefBuilder
    implements Builder<SalonServiceMasterRef, SalonServiceMasterRefBuilder> {
  _$SalonServiceMasterRef? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterServiceId;
  String? get masterServiceId => _$this._masterServiceId;
  set masterServiceId(String? masterServiceId) =>
      _$this._masterServiceId = masterServiceId;

  SalonServiceMasterRefBuilder() {
    SalonServiceMasterRef._defaults(this);
  }

  SalonServiceMasterRefBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _masterServiceId = $v.masterServiceId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonServiceMasterRef other) {
    _$v = other as _$SalonServiceMasterRef;
  }

  @override
  void update(void Function(SalonServiceMasterRefBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonServiceMasterRef build() => _build();

  _$SalonServiceMasterRef _build() {
    final _$result = _$v ??
        _$SalonServiceMasterRef._(
          masterId: BuiltValueNullFieldError.checkNotNull(
              masterId, r'SalonServiceMasterRef', 'masterId'),
          masterServiceId: BuiltValueNullFieldError.checkNotNull(
              masterServiceId, r'SalonServiceMasterRef', 'masterServiceId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
