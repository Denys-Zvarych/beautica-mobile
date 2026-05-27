// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'oblast_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OblastResponse extends OblastResponse {
  @override
  final String? id;
  @override
  final String? katotthCode;
  @override
  final String? nameUk;
  @override
  final String? nameEn;

  factory _$OblastResponse([void Function(OblastResponseBuilder)? updates]) =>
      (OblastResponseBuilder()..update(updates))._build();

  _$OblastResponse._({this.id, this.katotthCode, this.nameUk, this.nameEn})
      : super._();
  @override
  OblastResponse rebuild(void Function(OblastResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OblastResponseBuilder toBuilder() => OblastResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OblastResponse &&
        id == other.id &&
        katotthCode == other.katotthCode &&
        nameUk == other.nameUk &&
        nameEn == other.nameEn;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, katotthCode.hashCode);
    _$hash = $jc(_$hash, nameUk.hashCode);
    _$hash = $jc(_$hash, nameEn.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OblastResponse')
          ..add('id', id)
          ..add('katotthCode', katotthCode)
          ..add('nameUk', nameUk)
          ..add('nameEn', nameEn))
        .toString();
  }
}

class OblastResponseBuilder
    implements Builder<OblastResponse, OblastResponseBuilder> {
  _$OblastResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _katotthCode;
  String? get katotthCode => _$this._katotthCode;
  set katotthCode(String? katotthCode) => _$this._katotthCode = katotthCode;

  String? _nameUk;
  String? get nameUk => _$this._nameUk;
  set nameUk(String? nameUk) => _$this._nameUk = nameUk;

  String? _nameEn;
  String? get nameEn => _$this._nameEn;
  set nameEn(String? nameEn) => _$this._nameEn = nameEn;

  OblastResponseBuilder() {
    OblastResponse._defaults(this);
  }

  OblastResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _katotthCode = $v.katotthCode;
      _nameUk = $v.nameUk;
      _nameEn = $v.nameEn;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OblastResponse other) {
    _$v = other as _$OblastResponse;
  }

  @override
  void update(void Function(OblastResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OblastResponse build() => _build();

  _$OblastResponse _build() {
    final _$result = _$v ??
        _$OblastResponse._(
          id: id,
          katotthCode: katotthCode,
          nameUk: nameUk,
          nameEn: nameEn,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
