// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_device_token_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegisterDeviceTokenRequest extends RegisterDeviceTokenRequest {
  @override
  final String token;
  @override
  final String platform;

  factory _$RegisterDeviceTokenRequest(
          [void Function(RegisterDeviceTokenRequestBuilder)? updates]) =>
      (RegisterDeviceTokenRequestBuilder()..update(updates))._build();

  _$RegisterDeviceTokenRequest._({required this.token, required this.platform})
      : super._();
  @override
  RegisterDeviceTokenRequest rebuild(
          void Function(RegisterDeviceTokenRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegisterDeviceTokenRequestBuilder toBuilder() =>
      RegisterDeviceTokenRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegisterDeviceTokenRequest &&
        token == other.token &&
        platform == other.platform;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegisterDeviceTokenRequest')
          ..add('token', token)
          ..add('platform', platform))
        .toString();
  }
}

class RegisterDeviceTokenRequestBuilder
    implements
        Builder<RegisterDeviceTokenRequest, RegisterDeviceTokenRequestBuilder> {
  _$RegisterDeviceTokenRequest? _$v;

  String? _token;
  String? get token => _$this._token;
  set token(String? token) => _$this._token = token;

  String? _platform;
  String? get platform => _$this._platform;
  set platform(String? platform) => _$this._platform = platform;

  RegisterDeviceTokenRequestBuilder() {
    RegisterDeviceTokenRequest._defaults(this);
  }

  RegisterDeviceTokenRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _token = $v.token;
      _platform = $v.platform;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegisterDeviceTokenRequest other) {
    _$v = other as _$RegisterDeviceTokenRequest;
  }

  @override
  void update(void Function(RegisterDeviceTokenRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegisterDeviceTokenRequest build() => _build();

  _$RegisterDeviceTokenRequest _build() {
    final _$result = _$v ??
        _$RegisterDeviceTokenRequest._(
          token: BuiltValueNullFieldError.checkNotNull(
              token, r'RegisterDeviceTokenRequest', 'token'),
          platform: BuiltValueNullFieldError.checkNotNull(
              platform, r'RegisterDeviceTokenRequest', 'platform'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
