// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_telegram_link_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestTelegramLinkResponse extends GuestTelegramLinkResponse {
  @override
  final String? url;
  @override
  final DateTime? expiresAt;
  @override
  final bool? alreadyLinked;

  factory _$GuestTelegramLinkResponse(
          [void Function(GuestTelegramLinkResponseBuilder)? updates]) =>
      (GuestTelegramLinkResponseBuilder()..update(updates))._build();

  _$GuestTelegramLinkResponse._({this.url, this.expiresAt, this.alreadyLinked})
      : super._();
  @override
  GuestTelegramLinkResponse rebuild(
          void Function(GuestTelegramLinkResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestTelegramLinkResponseBuilder toBuilder() =>
      GuestTelegramLinkResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestTelegramLinkResponse &&
        url == other.url &&
        expiresAt == other.expiresAt &&
        alreadyLinked == other.alreadyLinked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jc(_$hash, alreadyLinked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestTelegramLinkResponse')
          ..add('url', url)
          ..add('expiresAt', expiresAt)
          ..add('alreadyLinked', alreadyLinked))
        .toString();
  }
}

class GuestTelegramLinkResponseBuilder
    implements
        Builder<GuestTelegramLinkResponse, GuestTelegramLinkResponseBuilder> {
  _$GuestTelegramLinkResponse? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  bool? _alreadyLinked;
  bool? get alreadyLinked => _$this._alreadyLinked;
  set alreadyLinked(bool? alreadyLinked) =>
      _$this._alreadyLinked = alreadyLinked;

  GuestTelegramLinkResponseBuilder() {
    GuestTelegramLinkResponse._defaults(this);
  }

  GuestTelegramLinkResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _expiresAt = $v.expiresAt;
      _alreadyLinked = $v.alreadyLinked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestTelegramLinkResponse other) {
    _$v = other as _$GuestTelegramLinkResponse;
  }

  @override
  void update(void Function(GuestTelegramLinkResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestTelegramLinkResponse build() => _build();

  _$GuestTelegramLinkResponse _build() {
    final _$result = _$v ??
        _$GuestTelegramLinkResponse._(
          url: url,
          expiresAt: expiresAt,
          alreadyLinked: alreadyLinked,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
