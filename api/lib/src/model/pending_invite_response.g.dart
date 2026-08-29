// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_invite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PendingInviteResponse extends PendingInviteResponse {
  @override
  final String? inviteId;
  @override
  final String? recipientEmail;
  @override
  final String? role;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? expiresAt;

  factory _$PendingInviteResponse(
          [void Function(PendingInviteResponseBuilder)? updates]) =>
      (PendingInviteResponseBuilder()..update(updates))._build();

  _$PendingInviteResponse._(
      {this.inviteId,
      this.recipientEmail,
      this.role,
      this.createdAt,
      this.expiresAt})
      : super._();
  @override
  PendingInviteResponse rebuild(
          void Function(PendingInviteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PendingInviteResponseBuilder toBuilder() =>
      PendingInviteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PendingInviteResponse &&
        inviteId == other.inviteId &&
        recipientEmail == other.recipientEmail &&
        role == other.role &&
        createdAt == other.createdAt &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, inviteId.hashCode);
    _$hash = $jc(_$hash, recipientEmail.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PendingInviteResponse')
          ..add('inviteId', inviteId)
          ..add('recipientEmail', recipientEmail)
          ..add('role', role)
          ..add('createdAt', createdAt)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class PendingInviteResponseBuilder
    implements Builder<PendingInviteResponse, PendingInviteResponseBuilder> {
  _$PendingInviteResponse? _$v;

  String? _inviteId;
  String? get inviteId => _$this._inviteId;
  set inviteId(String? inviteId) => _$this._inviteId = inviteId;

  String? _recipientEmail;
  String? get recipientEmail => _$this._recipientEmail;
  set recipientEmail(String? recipientEmail) =>
      _$this._recipientEmail = recipientEmail;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  PendingInviteResponseBuilder() {
    PendingInviteResponse._defaults(this);
  }

  PendingInviteResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _inviteId = $v.inviteId;
      _recipientEmail = $v.recipientEmail;
      _role = $v.role;
      _createdAt = $v.createdAt;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PendingInviteResponse other) {
    _$v = other as _$PendingInviteResponse;
  }

  @override
  void update(void Function(PendingInviteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PendingInviteResponse build() => _build();

  _$PendingInviteResponse _build() {
    final _$result = _$v ??
        _$PendingInviteResponse._(
          inviteId: inviteId,
          recipientEmail: recipientEmail,
          role: role,
          createdAt: createdAt,
          expiresAt: expiresAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
