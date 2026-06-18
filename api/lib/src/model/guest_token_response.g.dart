// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_token_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestTokenResponse extends GuestTokenResponse {
  @override
  final String? guestToken;

  factory _$GuestTokenResponse(
          [void Function(GuestTokenResponseBuilder)? updates]) =>
      (GuestTokenResponseBuilder()..update(updates))._build();

  _$GuestTokenResponse._({this.guestToken}) : super._();
  @override
  GuestTokenResponse rebuild(
          void Function(GuestTokenResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestTokenResponseBuilder toBuilder() =>
      GuestTokenResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestTokenResponse && guestToken == other.guestToken;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, guestToken.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestTokenResponse')
          ..add('guestToken', guestToken))
        .toString();
  }
}

class GuestTokenResponseBuilder
    implements Builder<GuestTokenResponse, GuestTokenResponseBuilder> {
  _$GuestTokenResponse? _$v;

  String? _guestToken;
  String? get guestToken => _$this._guestToken;
  set guestToken(String? guestToken) => _$this._guestToken = guestToken;

  GuestTokenResponseBuilder() {
    GuestTokenResponse._defaults(this);
  }

  GuestTokenResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _guestToken = $v.guestToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestTokenResponse other) {
    _$v = other as _$GuestTokenResponse;
  }

  @override
  void update(void Function(GuestTokenResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestTokenResponse build() => _build();

  _$GuestTokenResponse _build() {
    final _$result = _$v ??
        _$GuestTokenResponse._(
          guestToken: guestToken,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
