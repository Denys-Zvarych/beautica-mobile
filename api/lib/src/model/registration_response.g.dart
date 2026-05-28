// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registration_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegistrationResponse extends RegistrationResponse {
  @override
  final String? message;
  @override
  final String? email;

  factory _$RegistrationResponse(
          [void Function(RegistrationResponseBuilder)? updates]) =>
      (RegistrationResponseBuilder()..update(updates))._build();

  _$RegistrationResponse._({this.message, this.email}) : super._();
  @override
  RegistrationResponse rebuild(
          void Function(RegistrationResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegistrationResponseBuilder toBuilder() =>
      RegistrationResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegistrationResponse &&
        message == other.message &&
        email == other.email;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegistrationResponse')
          ..add('message', message)
          ..add('email', email))
        .toString();
  }
}

class RegistrationResponseBuilder
    implements Builder<RegistrationResponse, RegistrationResponseBuilder> {
  _$RegistrationResponse? _$v;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  RegistrationResponseBuilder() {
    RegistrationResponse._defaults(this);
  }

  RegistrationResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _message = $v.message;
      _email = $v.email;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegistrationResponse other) {
    _$v = other as _$RegistrationResponse;
  }

  @override
  void update(void Function(RegistrationResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegistrationResponse build() => _build();

  _$RegistrationResponse _build() {
    final _$result = _$v ??
        _$RegistrationResponse._(
          message: message,
          email: email,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
