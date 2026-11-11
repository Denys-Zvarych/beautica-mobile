// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_telegram_token_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestTelegramTokenRequest extends GuestTelegramTokenRequest {
  @override
  final String cancelToken;

  factory _$GuestTelegramTokenRequest(
          [void Function(GuestTelegramTokenRequestBuilder)? updates]) =>
      (GuestTelegramTokenRequestBuilder()..update(updates))._build();

  _$GuestTelegramTokenRequest._({required this.cancelToken}) : super._();
  @override
  GuestTelegramTokenRequest rebuild(
          void Function(GuestTelegramTokenRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestTelegramTokenRequestBuilder toBuilder() =>
      GuestTelegramTokenRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestTelegramTokenRequest &&
        cancelToken == other.cancelToken;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cancelToken.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestTelegramTokenRequest')
          ..add('cancelToken', cancelToken))
        .toString();
  }
}

class GuestTelegramTokenRequestBuilder
    implements
        Builder<GuestTelegramTokenRequest, GuestTelegramTokenRequestBuilder> {
  _$GuestTelegramTokenRequest? _$v;

  String? _cancelToken;
  String? get cancelToken => _$this._cancelToken;
  set cancelToken(String? cancelToken) => _$this._cancelToken = cancelToken;

  GuestTelegramTokenRequestBuilder() {
    GuestTelegramTokenRequest._defaults(this);
  }

  GuestTelegramTokenRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cancelToken = $v.cancelToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestTelegramTokenRequest other) {
    _$v = other as _$GuestTelegramTokenRequest;
  }

  @override
  void update(void Function(GuestTelegramTokenRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestTelegramTokenRequest build() => _build();

  _$GuestTelegramTokenRequest _build() {
    final _$result = _$v ??
        _$GuestTelegramTokenRequest._(
          cancelToken: BuiltValueNullFieldError.checkNotNull(
              cancelToken, r'GuestTelegramTokenRequest', 'cancelToken'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
