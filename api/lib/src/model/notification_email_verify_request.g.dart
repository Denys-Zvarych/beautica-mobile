// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_email_verify_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationEmailVerifyRequest extends NotificationEmailVerifyRequest {
  @override
  final String email;
  @override
  final String code;
  @override
  final String? currentPassword;

  factory _$NotificationEmailVerifyRequest(
          [void Function(NotificationEmailVerifyRequestBuilder)? updates]) =>
      (NotificationEmailVerifyRequestBuilder()..update(updates))._build();

  _$NotificationEmailVerifyRequest._(
      {required this.email, required this.code, this.currentPassword})
      : super._();
  @override
  NotificationEmailVerifyRequest rebuild(
          void Function(NotificationEmailVerifyRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NotificationEmailVerifyRequestBuilder toBuilder() =>
      NotificationEmailVerifyRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationEmailVerifyRequest &&
        email == other.email &&
        code == other.code &&
        currentPassword == other.currentPassword;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, currentPassword.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationEmailVerifyRequest')
          ..add('email', email)
          ..add('code', code)
          ..add('currentPassword', currentPassword))
        .toString();
  }
}

class NotificationEmailVerifyRequestBuilder
    implements
        Builder<NotificationEmailVerifyRequest,
            NotificationEmailVerifyRequestBuilder> {
  _$NotificationEmailVerifyRequest? _$v;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _currentPassword;
  String? get currentPassword => _$this._currentPassword;
  set currentPassword(String? currentPassword) =>
      _$this._currentPassword = currentPassword;

  NotificationEmailVerifyRequestBuilder() {
    NotificationEmailVerifyRequest._defaults(this);
  }

  NotificationEmailVerifyRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _email = $v.email;
      _code = $v.code;
      _currentPassword = $v.currentPassword;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationEmailVerifyRequest other) {
    _$v = other as _$NotificationEmailVerifyRequest;
  }

  @override
  void update(void Function(NotificationEmailVerifyRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationEmailVerifyRequest build() => _build();

  _$NotificationEmailVerifyRequest _build() {
    final _$result = _$v ??
        _$NotificationEmailVerifyRequest._(
          email: BuiltValueNullFieldError.checkNotNull(
              email, r'NotificationEmailVerifyRequest', 'email'),
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'NotificationEmailVerifyRequest', 'code'),
          currentPassword: currentPassword,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
