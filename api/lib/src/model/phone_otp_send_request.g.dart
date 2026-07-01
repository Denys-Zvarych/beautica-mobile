// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phone_otp_send_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhoneOtpSendRequest extends PhoneOtpSendRequest {
  @override
  final String phone;

  factory _$PhoneOtpSendRequest(
          [void Function(PhoneOtpSendRequestBuilder)? updates]) =>
      (PhoneOtpSendRequestBuilder()..update(updates))._build();

  _$PhoneOtpSendRequest._({required this.phone}) : super._();
  @override
  PhoneOtpSendRequest rebuild(
          void Function(PhoneOtpSendRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhoneOtpSendRequestBuilder toBuilder() =>
      PhoneOtpSendRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhoneOtpSendRequest && phone == other.phone;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhoneOtpSendRequest')
          ..add('phone', phone))
        .toString();
  }
}

class PhoneOtpSendRequestBuilder
    implements Builder<PhoneOtpSendRequest, PhoneOtpSendRequestBuilder> {
  _$PhoneOtpSendRequest? _$v;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  PhoneOtpSendRequestBuilder() {
    PhoneOtpSendRequest._defaults(this);
  }

  PhoneOtpSendRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phone = $v.phone;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhoneOtpSendRequest other) {
    _$v = other as _$PhoneOtpSendRequest;
  }

  @override
  void update(void Function(PhoneOtpSendRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhoneOtpSendRequest build() => _build();

  _$PhoneOtpSendRequest _build() {
    final _$result = _$v ??
        _$PhoneOtpSendRequest._(
          phone: BuiltValueNullFieldError.checkNotNull(
              phone, r'PhoneOtpSendRequest', 'phone'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
