// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phone_otp_verify_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhoneOtpVerifyRequest extends PhoneOtpVerifyRequest {
  @override
  final String phone;
  @override
  final String code;

  factory _$PhoneOtpVerifyRequest(
          [void Function(PhoneOtpVerifyRequestBuilder)? updates]) =>
      (PhoneOtpVerifyRequestBuilder()..update(updates))._build();

  _$PhoneOtpVerifyRequest._({required this.phone, required this.code})
      : super._();
  @override
  PhoneOtpVerifyRequest rebuild(
          void Function(PhoneOtpVerifyRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhoneOtpVerifyRequestBuilder toBuilder() =>
      PhoneOtpVerifyRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhoneOtpVerifyRequest &&
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
    return (newBuiltValueToStringHelper(r'PhoneOtpVerifyRequest')
          ..add('phone', phone)
          ..add('code', code))
        .toString();
  }
}

class PhoneOtpVerifyRequestBuilder
    implements Builder<PhoneOtpVerifyRequest, PhoneOtpVerifyRequestBuilder> {
  _$PhoneOtpVerifyRequest? _$v;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  PhoneOtpVerifyRequestBuilder() {
    PhoneOtpVerifyRequest._defaults(this);
  }

  PhoneOtpVerifyRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phone = $v.phone;
      _code = $v.code;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhoneOtpVerifyRequest other) {
    _$v = other as _$PhoneOtpVerifyRequest;
  }

  @override
  void update(void Function(PhoneOtpVerifyRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhoneOtpVerifyRequest build() => _build();

  _$PhoneOtpVerifyRequest _build() {
    final _$result = _$v ??
        _$PhoneOtpVerifyRequest._(
          phone: BuiltValueNullFieldError.checkNotNull(
              phone, r'PhoneOtpVerifyRequest', 'phone'),
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'PhoneOtpVerifyRequest', 'code'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
