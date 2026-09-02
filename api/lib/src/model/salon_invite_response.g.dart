// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_invite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonInviteResponse extends SalonInviteResponse {
  @override
  final String? inviteId;
  @override
  final String? recipientEmail;
  @override
  final String? role;
  @override
  final String? status;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? expiresAt;

  factory _$SalonInviteResponse(
          [void Function(SalonInviteResponseBuilder)? updates]) =>
      (SalonInviteResponseBuilder()..update(updates))._build();

  _$SalonInviteResponse._(
      {this.inviteId,
      this.recipientEmail,
      this.role,
      this.status,
      this.createdAt,
      this.expiresAt})
      : super._();
  @override
  SalonInviteResponse rebuild(
          void Function(SalonInviteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonInviteResponseBuilder toBuilder() =>
      SalonInviteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonInviteResponse &&
        inviteId == other.inviteId &&
        recipientEmail == other.recipientEmail &&
        role == other.role &&
        status == other.status &&
        createdAt == other.createdAt &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, inviteId.hashCode);
    _$hash = $jc(_$hash, recipientEmail.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonInviteResponse')
          ..add('inviteId', inviteId)
          ..add('recipientEmail', recipientEmail)
          ..add('role', role)
          ..add('status', status)
          ..add('createdAt', createdAt)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class SalonInviteResponseBuilder
    implements Builder<SalonInviteResponse, SalonInviteResponseBuilder> {
  _$SalonInviteResponse? _$v;

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

  String? _status;
  String? get status => _$this._status;
  set status(String? status) => _$this._status = status;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  SalonInviteResponseBuilder() {
    SalonInviteResponse._defaults(this);
  }

  SalonInviteResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _inviteId = $v.inviteId;
      _recipientEmail = $v.recipientEmail;
      _role = $v.role;
      _status = $v.status;
      _createdAt = $v.createdAt;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonInviteResponse other) {
    _$v = other as _$SalonInviteResponse;
  }

  @override
  void update(void Function(SalonInviteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonInviteResponse build() => _build();

  _$SalonInviteResponse _build() {
    final _$result = _$v ??
        _$SalonInviteResponse._(
          inviteId: inviteId,
          recipientEmail: recipientEmail,
          role: role,
          status: status,
          createdAt: createdAt,
          expiresAt: expiresAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
