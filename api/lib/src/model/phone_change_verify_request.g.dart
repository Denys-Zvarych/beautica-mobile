// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phone_change_verify_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhoneChangeVerifyRequest extends PhoneChangeVerifyRequest {
  @override
  final String phone;
  @override
  final String code;
  @override
  final String? currentPassword;

  factory _$PhoneChangeVerifyRequest(
          [void Function(PhoneChangeVerifyRequestBuilder)? updates]) =>
      (PhoneChangeVerifyRequestBuilder()..update(updates))._build();

  _$PhoneChangeVerifyRequest._(
      {required this.phone, required this.code, this.currentPassword})
      : super._();
  @override
  PhoneChangeVerifyRequest rebuild(
          void Function(PhoneChangeVerifyRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhoneChangeVerifyRequestBuilder toBuilder() =>
      PhoneChangeVerifyRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhoneChangeVerifyRequest &&
        phone == other.phone &&
        code == other.code &&
        currentPassword == other.currentPassword;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, currentPassword.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhoneChangeVerifyRequest')
          ..add('phone', phone)
          ..add('code', code)
          ..add('currentPassword', currentPassword))
        .toString();
  }
}

class PhoneChangeVerifyRequestBuilder
    implements
        Builder<PhoneChangeVerifyRequest, PhoneChangeVerifyRequestBuilder> {
  _$PhoneChangeVerifyRequest? _$v;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _currentPassword;
  String? get currentPassword => _$this._currentPassword;
  set currentPassword(String? currentPassword) =>
      _$this._currentPassword = currentPassword;

  PhoneChangeVerifyRequestBuilder() {
    PhoneChangeVerifyRequest._defaults(this);
  }

  PhoneChangeVerifyRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phone = $v.phone;
      _code = $v.code;
      _currentPassword = $v.currentPassword;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhoneChangeVerifyRequest other) {
    _$v = other as _$PhoneChangeVerifyRequest;
  }

  @override
  void update(void Function(PhoneChangeVerifyRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhoneChangeVerifyRequest build() => _build();

  _$PhoneChangeVerifyRequest _build() {
    final _$result = _$v ??
        _$PhoneChangeVerifyRequest._(
          phone: BuiltValueNullFieldError.checkNotNull(
              phone, r'PhoneChangeVerifyRequest', 'phone'),
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'PhoneChangeVerifyRequest', 'code'),
          currentPassword: currentPassword,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
