// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'city_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CityResponse extends CityResponse {
  @override
  final String? id;
  @override
  final String? oblastId;
  @override
  final String? katotthCode;
  @override
  final String? nameUk;
  @override
  final String? nameEn;
  @override
  final bool? hasDistricts;

  factory _$CityResponse([void Function(CityResponseBuilder)? updates]) =>
      (CityResponseBuilder()..update(updates))._build();

  _$CityResponse._(
      {this.id,
      this.oblastId,
      this.katotthCode,
      this.nameUk,
      this.nameEn,
      this.hasDistricts})
      : super._();
  @override
  CityResponse rebuild(void Function(CityResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CityResponseBuilder toBuilder() => CityResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CityResponse &&
        id == other.id &&
        oblastId == other.oblastId &&
        katotthCode == other.katotthCode &&
        nameUk == other.nameUk &&
        nameEn == other.nameEn &&
        hasDistricts == other.hasDistricts;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, oblastId.hashCode);
    _$hash = $jc(_$hash, katotthCode.hashCode);
    _$hash = $jc(_$hash, nameUk.hashCode);
    _$hash = $jc(_$hash, nameEn.hashCode);
    _$hash = $jc(_$hash, hasDistricts.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CityResponse')
          ..add('id', id)
          ..add('oblastId', oblastId)
          ..add('katotthCode', katotthCode)
          ..add('nameUk', nameUk)
          ..add('nameEn', nameEn)
          ..add('hasDistricts', hasDistricts))
        .toString();
  }
}

class CityResponseBuilder
    implements Builder<CityResponse, CityResponseBuilder> {
  _$CityResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _oblastId;
  String? get oblastId => _$this._oblastId;
  set oblastId(String? oblastId) => _$this._oblastId = oblastId;

  String? _katotthCode;
  String? get katotthCode => _$this._katotthCode;
  set katotthCode(String? katotthCode) => _$this._katotthCode = katotthCode;

  String? _nameUk;
  String? get nameUk => _$this._nameUk;
  set nameUk(String? nameUk) => _$this._nameUk = nameUk;

  String? _nameEn;
  String? get nameEn => _$this._nameEn;
  set nameEn(String? nameEn) => _$this._nameEn = nameEn;

  bool? _hasDistricts;
  bool? get hasDistricts => _$this._hasDistricts;
  set hasDistricts(bool? hasDistricts) => _$this._hasDistricts = hasDistricts;

  CityResponseBuilder() {
    CityResponse._defaults(this);
  }

  CityResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _oblastId = $v.oblastId;
      _katotthCode = $v.katotthCode;
      _nameUk = $v.nameUk;
      _nameEn = $v.nameEn;
      _hasDistricts = $v.hasDistricts;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CityResponse other) {
    _$v = other as _$CityResponse;
  }

  @override
  void update(void Function(CityResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CityResponse build() => _build();

  _$CityResponse _build() {
    final _$result = _$v ??
        _$CityResponse._(
          id: id,
          oblastId: oblastId,
          katotthCode: katotthCode,
          nameUk: nameUk,
          nameEn: nameEn,
          hasDistricts: hasDistricts,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
