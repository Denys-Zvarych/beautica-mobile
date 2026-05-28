// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'city_district_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CityDistrictResponse extends CityDistrictResponse {
  @override
  final String? id;
  @override
  final String? cityId;
  @override
  final String? katotthCode;
  @override
  final String? nameUk;
  @override
  final String? nameEn;

  factory _$CityDistrictResponse(
          [void Function(CityDistrictResponseBuilder)? updates]) =>
      (CityDistrictResponseBuilder()..update(updates))._build();

  _$CityDistrictResponse._(
      {this.id, this.cityId, this.katotthCode, this.nameUk, this.nameEn})
      : super._();
  @override
  CityDistrictResponse rebuild(
          void Function(CityDistrictResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CityDistrictResponseBuilder toBuilder() =>
      CityDistrictResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CityDistrictResponse &&
        id == other.id &&
        cityId == other.cityId &&
        katotthCode == other.katotthCode &&
        nameUk == other.nameUk &&
        nameEn == other.nameEn;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, katotthCode.hashCode);
    _$hash = $jc(_$hash, nameUk.hashCode);
    _$hash = $jc(_$hash, nameEn.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CityDistrictResponse')
          ..add('id', id)
          ..add('cityId', cityId)
          ..add('katotthCode', katotthCode)
          ..add('nameUk', nameUk)
          ..add('nameEn', nameEn))
        .toString();
  }
}

class CityDistrictResponseBuilder
    implements Builder<CityDistrictResponse, CityDistrictResponseBuilder> {
  _$CityDistrictResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _cityId;
  String? get cityId => _$this._cityId;
  set cityId(String? cityId) => _$this._cityId = cityId;

  String? _katotthCode;
  String? get katotthCode => _$this._katotthCode;
  set katotthCode(String? katotthCode) => _$this._katotthCode = katotthCode;

  String? _nameUk;
  String? get nameUk => _$this._nameUk;
  set nameUk(String? nameUk) => _$this._nameUk = nameUk;

  String? _nameEn;
  String? get nameEn => _$this._nameEn;
  set nameEn(String? nameEn) => _$this._nameEn = nameEn;

  CityDistrictResponseBuilder() {
    CityDistrictResponse._defaults(this);
  }

  CityDistrictResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _cityId = $v.cityId;
      _katotthCode = $v.katotthCode;
      _nameUk = $v.nameUk;
      _nameEn = $v.nameEn;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CityDistrictResponse other) {
    _$v = other as _$CityDistrictResponse;
  }

  @override
  void update(void Function(CityDistrictResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CityDistrictResponse build() => _build();

  _$CityDistrictResponse _build() {
    final _$result = _$v ??
        _$CityDistrictResponse._(
          id: id,
          cityId: cityId,
          katotthCode: katotthCode,
          nameUk: nameUk,
          nameEn: nameEn,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
