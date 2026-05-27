// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'avatar_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AvatarResponse extends AvatarResponse {
  @override
  final String? avatarUrl;

  factory _$AvatarResponse([void Function(AvatarResponseBuilder)? updates]) =>
      (AvatarResponseBuilder()..update(updates))._build();

  _$AvatarResponse._({this.avatarUrl}) : super._();
  @override
  AvatarResponse rebuild(void Function(AvatarResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AvatarResponseBuilder toBuilder() => AvatarResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AvatarResponse && avatarUrl == other.avatarUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AvatarResponse')
          ..add('avatarUrl', avatarUrl))
        .toString();
  }
}

class AvatarResponseBuilder
    implements Builder<AvatarResponse, AvatarResponseBuilder> {
  _$AvatarResponse? _$v;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  AvatarResponseBuilder() {
    AvatarResponse._defaults(this);
  }

  AvatarResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _avatarUrl = $v.avatarUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AvatarResponse other) {
    _$v = other as _$AvatarResponse;
  }

  @override
  void update(void Function(AvatarResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AvatarResponse build() => _build();

  _$AvatarResponse _build() {
    final _$result = _$v ??
        _$AvatarResponse._(
          avatarUrl: avatarUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
