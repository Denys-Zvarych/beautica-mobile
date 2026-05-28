// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unregister_device_token_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UnregisterDeviceTokenRequest extends UnregisterDeviceTokenRequest {
  @override
  final String token;

  factory _$UnregisterDeviceTokenRequest(
          [void Function(UnregisterDeviceTokenRequestBuilder)? updates]) =>
      (UnregisterDeviceTokenRequestBuilder()..update(updates))._build();

  _$UnregisterDeviceTokenRequest._({required this.token}) : super._();
  @override
  UnregisterDeviceTokenRequest rebuild(
          void Function(UnregisterDeviceTokenRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UnregisterDeviceTokenRequestBuilder toBuilder() =>
      UnregisterDeviceTokenRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UnregisterDeviceTokenRequest && token == other.token;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UnregisterDeviceTokenRequest')
          ..add('token', token))
        .toString();
  }
}

class UnregisterDeviceTokenRequestBuilder
    implements
        Builder<UnregisterDeviceTokenRequest,
            UnregisterDeviceTokenRequestBuilder> {
  _$UnregisterDeviceTokenRequest? _$v;

  String? _token;
  String? get token => _$this._token;
  set token(String? token) => _$this._token = token;

  UnregisterDeviceTokenRequestBuilder() {
    UnregisterDeviceTokenRequest._defaults(this);
  }

  UnregisterDeviceTokenRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _token = $v.token;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UnregisterDeviceTokenRequest other) {
    _$v = other as _$UnregisterDeviceTokenRequest;
  }

  @override
  void update(void Function(UnregisterDeviceTokenRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UnregisterDeviceTokenRequest build() => _build();

  _$UnregisterDeviceTokenRequest _build() {
    final _$result = _$v ??
        _$UnregisterDeviceTokenRequest._(
          token: BuiltValueNullFieldError.checkNotNull(
              token, r'UnregisterDeviceTokenRequest', 'token'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
