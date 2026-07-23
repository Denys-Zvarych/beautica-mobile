// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reset_password_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ResetPasswordRequest extends ResetPasswordRequest {
  @override
  final String resetTicket;
  @override
  final String newPassword;

  factory _$ResetPasswordRequest(
          [void Function(ResetPasswordRequestBuilder)? updates]) =>
      (ResetPasswordRequestBuilder()..update(updates))._build();

  _$ResetPasswordRequest._(
      {required this.resetTicket, required this.newPassword})
      : super._();
  @override
  ResetPasswordRequest rebuild(
          void Function(ResetPasswordRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ResetPasswordRequestBuilder toBuilder() =>
      ResetPasswordRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ResetPasswordRequest &&
        resetTicket == other.resetTicket &&
        newPassword == other.newPassword;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, resetTicket.hashCode);
    _$hash = $jc(_$hash, newPassword.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ResetPasswordRequest')
          ..add('resetTicket', resetTicket)
          ..add('newPassword', newPassword))
        .toString();
  }
}

class ResetPasswordRequestBuilder
    implements Builder<ResetPasswordRequest, ResetPasswordRequestBuilder> {
  _$ResetPasswordRequest? _$v;

  String? _resetTicket;
  String? get resetTicket => _$this._resetTicket;
  set resetTicket(String? resetTicket) => _$this._resetTicket = resetTicket;

  String? _newPassword;
  String? get newPassword => _$this._newPassword;
  set newPassword(String? newPassword) => _$this._newPassword = newPassword;

  ResetPasswordRequestBuilder() {
    ResetPasswordRequest._defaults(this);
  }

  ResetPasswordRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _resetTicket = $v.resetTicket;
      _newPassword = $v.newPassword;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ResetPasswordRequest other) {
    _$v = other as _$ResetPasswordRequest;
  }

  @override
  void update(void Function(ResetPasswordRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ResetPasswordRequest build() => _build();

  _$ResetPasswordRequest _build() {
    final _$result = _$v ??
        _$ResetPasswordRequest._(
          resetTicket: BuiltValueNullFieldError.checkNotNull(
              resetTicket, r'ResetPasswordRequest', 'resetTicket'),
          newPassword: BuiltValueNullFieldError.checkNotNull(
              newPassword, r'ResetPasswordRequest', 'newPassword'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
