// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'verify_password_reset_otp_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$VerifyPasswordResetOtpRequest extends VerifyPasswordResetOtpRequest {
  @override
  final String email;
  @override
  final String code;

  factory _$VerifyPasswordResetOtpRequest(
          [void Function(VerifyPasswordResetOtpRequestBuilder)? updates]) =>
      (VerifyPasswordResetOtpRequestBuilder()..update(updates))._build();

  _$VerifyPasswordResetOtpRequest._({required this.email, required this.code})
      : super._();
  @override
  VerifyPasswordResetOtpRequest rebuild(
          void Function(VerifyPasswordResetOtpRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  VerifyPasswordResetOtpRequestBuilder toBuilder() =>
      VerifyPasswordResetOtpRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is VerifyPasswordResetOtpRequest &&
        email == other.email &&
        code == other.code;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'VerifyPasswordResetOtpRequest')
          ..add('email', email)
          ..add('code', code))
        .toString();
  }
}

class VerifyPasswordResetOtpRequestBuilder
    implements
        Builder<VerifyPasswordResetOtpRequest,
            VerifyPasswordResetOtpRequestBuilder> {
  _$VerifyPasswordResetOtpRequest? _$v;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  VerifyPasswordResetOtpRequestBuilder() {
    VerifyPasswordResetOtpRequest._defaults(this);
  }

  VerifyPasswordResetOtpRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _email = $v.email;
      _code = $v.code;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(VerifyPasswordResetOtpRequest other) {
    _$v = other as _$VerifyPasswordResetOtpRequest;
  }

  @override
  void update(void Function(VerifyPasswordResetOtpRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  VerifyPasswordResetOtpRequest build() => _build();

  _$VerifyPasswordResetOtpRequest _build() {
    final _$result = _$v ??
        _$VerifyPasswordResetOtpRequest._(
          email: BuiltValueNullFieldError.checkNotNull(
              email, r'VerifyPasswordResetOtpRequest', 'email'),
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'VerifyPasswordResetOtpRequest', 'code'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
