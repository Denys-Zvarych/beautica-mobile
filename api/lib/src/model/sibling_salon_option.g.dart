// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sibling_salon_option.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SiblingSalonOption extends SiblingSalonOption {
  @override
  final String id;
  @override
  final String name;
  @override
  final String? street;
  @override
  final String? buildingNo;

  factory _$SiblingSalonOption(
          [void Function(SiblingSalonOptionBuilder)? updates]) =>
      (SiblingSalonOptionBuilder()..update(updates))._build();

  _$SiblingSalonOption._(
      {required this.id, required this.name, this.street, this.buildingNo})
      : super._();
  @override
  SiblingSalonOption rebuild(
          void Function(SiblingSalonOptionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SiblingSalonOptionBuilder toBuilder() =>
      SiblingSalonOptionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SiblingSalonOption &&
        id == other.id &&
        name == other.name &&
        street == other.street &&
        buildingNo == other.buildingNo;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SiblingSalonOption')
          ..add('id', id)
          ..add('name', name)
          ..add('street', street)
          ..add('buildingNo', buildingNo))
        .toString();
  }
}

class SiblingSalonOptionBuilder
    implements Builder<SiblingSalonOption, SiblingSalonOptionBuilder> {
  _$SiblingSalonOption? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  SiblingSalonOptionBuilder() {
    SiblingSalonOption._defaults(this);
  }

  SiblingSalonOptionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SiblingSalonOption other) {
    _$v = other as _$SiblingSalonOption;
  }

  @override
  void update(void Function(SiblingSalonOptionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SiblingSalonOption build() => _build();

  _$SiblingSalonOption _build() {
    final _$result = _$v ??
        _$SiblingSalonOption._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'SiblingSalonOption', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'SiblingSalonOption', 'name'),
          street: street,
          buildingNo: buildingNo,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
