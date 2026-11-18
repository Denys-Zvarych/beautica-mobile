// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registration_otp_verify_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegistrationOtpVerifyRequest extends RegistrationOtpVerifyRequest {
  @override
  final String phone;
  @override
  final String code;

  factory _$RegistrationOtpVerifyRequest(
          [void Function(RegistrationOtpVerifyRequestBuilder)? updates]) =>
      (RegistrationOtpVerifyRequestBuilder()..update(updates))._build();

  _$RegistrationOtpVerifyRequest._({required this.phone, required this.code})
      : super._();
  @override
  RegistrationOtpVerifyRequest rebuild(
          void Function(RegistrationOtpVerifyRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegistrationOtpVerifyRequestBuilder toBuilder() =>
      RegistrationOtpVerifyRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegistrationOtpVerifyRequest &&
        phone == other.phone &&
        code == other.code;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegistrationOtpVerifyRequest')
          ..add('phone', phone)
          ..add('code', code))
        .toString();
  }
}

class RegistrationOtpVerifyRequestBuilder
    implements
        Builder<RegistrationOtpVerifyRequest,
            RegistrationOtpVerifyRequestBuilder> {
  _$RegistrationOtpVerifyRequest? _$v;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  RegistrationOtpVerifyRequestBuilder() {
    RegistrationOtpVerifyRequest._defaults(this);
  }

  RegistrationOtpVerifyRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phone = $v.phone;
      _code = $v.code;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegistrationOtpVerifyRequest other) {
    _$v = other as _$RegistrationOtpVerifyRequest;
  }

  @override
  void update(void Function(RegistrationOtpVerifyRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegistrationOtpVerifyRequest build() => _build();

  _$RegistrationOtpVerifyRequest _build() {
    final _$result = _$v ??
        _$RegistrationOtpVerifyRequest._(
          phone: BuiltValueNullFieldError.checkNotNull(
              phone, r'RegistrationOtpVerifyRequest', 'phone'),
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'RegistrationOtpVerifyRequest', 'code'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
