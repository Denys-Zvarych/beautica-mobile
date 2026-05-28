// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resend_verification_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ResendVerificationRequest extends ResendVerificationRequest {
  @override
  final String email;

  factory _$ResendVerificationRequest(
          [void Function(ResendVerificationRequestBuilder)? updates]) =>
      (ResendVerificationRequestBuilder()..update(updates))._build();

  _$ResendVerificationRequest._({required this.email}) : super._();
  @override
  ResendVerificationRequest rebuild(
          void Function(ResendVerificationRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ResendVerificationRequestBuilder toBuilder() =>
      ResendVerificationRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ResendVerificationRequest && email == other.email;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ResendVerificationRequest')
          ..add('email', email))
        .toString();
  }
}

class ResendVerificationRequestBuilder
    implements
        Builder<ResendVerificationRequest, ResendVerificationRequestBuilder> {
  _$ResendVerificationRequest? _$v;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  ResendVerificationRequestBuilder() {
    ResendVerificationRequest._defaults(this);
  }

  ResendVerificationRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _email = $v.email;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ResendVerificationRequest other) {
    _$v = other as _$ResendVerificationRequest;
  }

  @override
  void update(void Function(ResendVerificationRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ResendVerificationRequest build() => _build();

  _$ResendVerificationRequest _build() {
    final _$result = _$v ??
        _$ResendVerificationRequest._(
          email: BuiltValueNullFieldError.checkNotNull(
              email, r'ResendVerificationRequest', 'email'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
