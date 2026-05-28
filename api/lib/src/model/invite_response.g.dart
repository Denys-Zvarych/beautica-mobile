// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InviteResponse extends InviteResponse {
  @override
  final String? invitedEmail;
  @override
  final DateTime? expiresAt;

  factory _$InviteResponse([void Function(InviteResponseBuilder)? updates]) =>
      (InviteResponseBuilder()..update(updates))._build();

  _$InviteResponse._({this.invitedEmail, this.expiresAt}) : super._();
  @override
  InviteResponse rebuild(void Function(InviteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InviteResponseBuilder toBuilder() => InviteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InviteResponse &&
        invitedEmail == other.invitedEmail &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, invitedEmail.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InviteResponse')
          ..add('invitedEmail', invitedEmail)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class InviteResponseBuilder
    implements Builder<InviteResponse, InviteResponseBuilder> {
  _$InviteResponse? _$v;

  String? _invitedEmail;
  String? get invitedEmail => _$this._invitedEmail;
  set invitedEmail(String? invitedEmail) => _$this._invitedEmail = invitedEmail;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  InviteResponseBuilder() {
    InviteResponse._defaults(this);
  }

  InviteResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _invitedEmail = $v.invitedEmail;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InviteResponse other) {
    _$v = other as _$InviteResponse;
  }

  @override
  void update(void Function(InviteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InviteResponse build() => _build();

  _$InviteResponse _build() {
    final _$result = _$v ??
        _$InviteResponse._(
          invitedEmail: invitedEmail,
          expiresAt: expiresAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
