// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phone_otp_send_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhoneOtpSendRequest extends PhoneOtpSendRequest {
  @override
  final String phone;
  @override
  final bool privacyAccepted;
  @override
  final String privacyPolicyVersion;
  @override
  final String? turnstileToken;

  factory _$PhoneOtpSendRequest(
          [void Function(PhoneOtpSendRequestBuilder)? updates]) =>
      (PhoneOtpSendRequestBuilder()..update(updates))._build();

  _$PhoneOtpSendRequest._(
      {required this.phone,
      required this.privacyAccepted,
      required this.privacyPolicyVersion,
      this.turnstileToken})
      : super._();
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
    return other is PhoneOtpSendRequest &&
        phone == other.phone &&
        privacyAccepted == other.privacyAccepted &&
        privacyPolicyVersion == other.privacyPolicyVersion &&
        turnstileToken == other.turnstileToken;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, privacyAccepted.hashCode);
    _$hash = $jc(_$hash, privacyPolicyVersion.hashCode);
    _$hash = $jc(_$hash, turnstileToken.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhoneOtpSendRequest')
          ..add('phone', phone)
          ..add('privacyAccepted', privacyAccepted)
          ..add('privacyPolicyVersion', privacyPolicyVersion)
          ..add('turnstileToken', turnstileToken))
        .toString();
  }
}

class PhoneOtpSendRequestBuilder
    implements Builder<PhoneOtpSendRequest, PhoneOtpSendRequestBuilder> {
  _$PhoneOtpSendRequest? _$v;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  bool? _privacyAccepted;
  bool? get privacyAccepted => _$this._privacyAccepted;
  set privacyAccepted(bool? privacyAccepted) =>
      _$this._privacyAccepted = privacyAccepted;

  String? _privacyPolicyVersion;
  String? get privacyPolicyVersion => _$this._privacyPolicyVersion;
  set privacyPolicyVersion(String? privacyPolicyVersion) =>
      _$this._privacyPolicyVersion = privacyPolicyVersion;

  String? _turnstileToken;
  String? get turnstileToken => _$this._turnstileToken;
  set turnstileToken(String? turnstileToken) =>
      _$this._turnstileToken = turnstileToken;

  PhoneOtpSendRequestBuilder() {
    PhoneOtpSendRequest._defaults(this);
  }

  PhoneOtpSendRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phone = $v.phone;
      _privacyAccepted = $v.privacyAccepted;
      _privacyPolicyVersion = $v.privacyPolicyVersion;
      _turnstileToken = $v.turnstileToken;
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
          privacyAccepted: BuiltValueNullFieldError.checkNotNull(
              privacyAccepted, r'PhoneOtpSendRequest', 'privacyAccepted'),
          privacyPolicyVersion: BuiltValueNullFieldError.checkNotNull(
              privacyPolicyVersion,
              r'PhoneOtpSendRequest',
              'privacyPolicyVersion'),
          turnstileToken: turnstileToken,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
