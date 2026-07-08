// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_admin_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonAdminResponse extends SalonAdminResponse {
  @override
  final String? userId;
  @override
  final String? email;
  @override
  final String? salonId;

  factory _$SalonAdminResponse(
          [void Function(SalonAdminResponseBuilder)? updates]) =>
      (SalonAdminResponseBuilder()..update(updates))._build();

  _$SalonAdminResponse._({this.userId, this.email, this.salonId}) : super._();
  @override
  SalonAdminResponse rebuild(
          void Function(SalonAdminResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonAdminResponseBuilder toBuilder() =>
      SalonAdminResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonAdminResponse &&
        userId == other.userId &&
        email == other.email &&
        salonId == other.salonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonAdminResponse')
          ..add('userId', userId)
          ..add('email', email)
          ..add('salonId', salonId))
        .toString();
  }
}

class SalonAdminResponseBuilder
    implements Builder<SalonAdminResponse, SalonAdminResponseBuilder> {
  _$SalonAdminResponse? _$v;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  SalonAdminResponseBuilder() {
    SalonAdminResponse._defaults(this);
  }

  SalonAdminResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _userId = $v.userId;
      _email = $v.email;
      _salonId = $v.salonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonAdminResponse other) {
    _$v = other as _$SalonAdminResponse;
  }

  @override
  void update(void Function(SalonAdminResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonAdminResponse build() => _build();

  _$SalonAdminResponse _build() {
    final _$result = _$v ??
        _$SalonAdminResponse._(
          userId: userId,
          email: email,
          salonId: salonId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
