// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_cancel_token.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestCancelToken extends GuestCancelToken {
  @override
  final String? value;
  @override
  final bool? legacy;

  factory _$GuestCancelToken(
          [void Function(GuestCancelTokenBuilder)? updates]) =>
      (GuestCancelTokenBuilder()..update(updates))._build();

  _$GuestCancelToken._({this.value, this.legacy}) : super._();
  @override
  GuestCancelToken rebuild(void Function(GuestCancelTokenBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestCancelTokenBuilder toBuilder() =>
      GuestCancelTokenBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestCancelToken &&
        value == other.value &&
        legacy == other.legacy;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, value.hashCode);
    _$hash = $jc(_$hash, legacy.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestCancelToken')
          ..add('value', value)
          ..add('legacy', legacy))
        .toString();
  }
}

class GuestCancelTokenBuilder
    implements Builder<GuestCancelToken, GuestCancelTokenBuilder> {
  _$GuestCancelToken? _$v;

  String? _value;
  String? get value => _$this._value;
  set value(String? value) => _$this._value = value;

  bool? _legacy;
  bool? get legacy => _$this._legacy;
  set legacy(bool? legacy) => _$this._legacy = legacy;

  GuestCancelTokenBuilder() {
    GuestCancelToken._defaults(this);
  }

  GuestCancelTokenBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _value = $v.value;
      _legacy = $v.legacy;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestCancelToken other) {
    _$v = other as _$GuestCancelToken;
  }

  @override
  void update(void Function(GuestCancelTokenBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestCancelToken build() => _build();

  _$GuestCancelToken _build() {
    final _$result = _$v ??
        _$GuestCancelToken._(
          value: value,
          legacy: legacy,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
