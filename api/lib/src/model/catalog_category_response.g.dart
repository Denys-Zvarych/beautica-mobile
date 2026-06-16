// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_category_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CatalogCategoryResponse extends CatalogCategoryResponse {
  @override
  final String? id;
  @override
  final String? nameUk;
  @override
  final String? nameEn;
  @override
  final int? sortOrder;

  factory _$CatalogCategoryResponse(
          [void Function(CatalogCategoryResponseBuilder)? updates]) =>
      (CatalogCategoryResponseBuilder()..update(updates))._build();

  _$CatalogCategoryResponse._(
      {this.id, this.nameUk, this.nameEn, this.sortOrder})
      : super._();
  @override
  CatalogCategoryResponse rebuild(
          void Function(CatalogCategoryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CatalogCategoryResponseBuilder toBuilder() =>
      CatalogCategoryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CatalogCategoryResponse &&
        id == other.id &&
        nameUk == other.nameUk &&
        nameEn == other.nameEn &&
        sortOrder == other.sortOrder;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, nameUk.hashCode);
    _$hash = $jc(_$hash, nameEn.hashCode);
    _$hash = $jc(_$hash, sortOrder.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CatalogCategoryResponse')
          ..add('id', id)
          ..add('nameUk', nameUk)
          ..add('nameEn', nameEn)
          ..add('sortOrder', sortOrder))
        .toString();
  }
}

class CatalogCategoryResponseBuilder
    implements
        Builder<CatalogCategoryResponse, CatalogCategoryResponseBuilder> {
  _$CatalogCategoryResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _nameUk;
  String? get nameUk => _$this._nameUk;
  set nameUk(String? nameUk) => _$this._nameUk = nameUk;

  String? _nameEn;
  String? get nameEn => _$this._nameEn;
  set nameEn(String? nameEn) => _$this._nameEn = nameEn;

  int? _sortOrder;
  int? get sortOrder => _$this._sortOrder;
  set sortOrder(int? sortOrder) => _$this._sortOrder = sortOrder;

  CatalogCategoryResponseBuilder() {
    CatalogCategoryResponse._defaults(this);
  }

  CatalogCategoryResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _nameUk = $v.nameUk;
      _nameEn = $v.nameEn;
      _sortOrder = $v.sortOrder;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CatalogCategoryResponse other) {
    _$v = other as _$CatalogCategoryResponse;
  }

  @override
  void update(void Function(CatalogCategoryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CatalogCategoryResponse build() => _build();

  _$CatalogCategoryResponse _build() {
    final _$result = _$v ??
        _$CatalogCategoryResponse._(
          id: id,
          nameUk: nameUk,
          nameEn: nameEn,
          sortOrder: sortOrder,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
