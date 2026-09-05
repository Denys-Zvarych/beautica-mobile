// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_deletion_blocked_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonDeletionBlockedResponse extends SalonDeletionBlockedResponse {
  @override
  final String? code;
  @override
  final int? affectedStaffCount;

  factory _$SalonDeletionBlockedResponse(
          [void Function(SalonDeletionBlockedResponseBuilder)? updates]) =>
      (SalonDeletionBlockedResponseBuilder()..update(updates))._build();

  _$SalonDeletionBlockedResponse._({this.code, this.affectedStaffCount})
      : super._();
  @override
  SalonDeletionBlockedResponse rebuild(
          void Function(SalonDeletionBlockedResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonDeletionBlockedResponseBuilder toBuilder() =>
      SalonDeletionBlockedResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonDeletionBlockedResponse &&
        code == other.code &&
        affectedStaffCount == other.affectedStaffCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, affectedStaffCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonDeletionBlockedResponse')
          ..add('code', code)
          ..add('affectedStaffCount', affectedStaffCount))
        .toString();
  }
}

class SalonDeletionBlockedResponseBuilder
    implements
        Builder<SalonDeletionBlockedResponse,
            SalonDeletionBlockedResponseBuilder> {
  _$SalonDeletionBlockedResponse? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  int? _affectedStaffCount;
  int? get affectedStaffCount => _$this._affectedStaffCount;
  set affectedStaffCount(int? affectedStaffCount) =>
      _$this._affectedStaffCount = affectedStaffCount;

  SalonDeletionBlockedResponseBuilder() {
    SalonDeletionBlockedResponse._defaults(this);
  }

  SalonDeletionBlockedResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _affectedStaffCount = $v.affectedStaffCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonDeletionBlockedResponse other) {
    _$v = other as _$SalonDeletionBlockedResponse;
  }

  @override
  void update(void Function(SalonDeletionBlockedResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonDeletionBlockedResponse build() => _build();

  _$SalonDeletionBlockedResponse _build() {
    final _$result = _$v ??
        _$SalonDeletionBlockedResponse._(
          code: code,
          affectedStaffCount: affectedStaffCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
