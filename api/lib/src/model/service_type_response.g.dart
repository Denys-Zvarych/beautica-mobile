// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_type_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServiceTypeResponse extends ServiceTypeResponse {
  @override
  final String? id;
  @override
  final String? categoryId;
  @override
  final String? nameUk;
  @override
  final String? nameEn;
  @override
  final String? slug;

  factory _$ServiceTypeResponse(
          [void Function(ServiceTypeResponseBuilder)? updates]) =>
      (ServiceTypeResponseBuilder()..update(updates))._build();

  _$ServiceTypeResponse._(
      {this.id, this.categoryId, this.nameUk, this.nameEn, this.slug})
      : super._();
  @override
  ServiceTypeResponse rebuild(
          void Function(ServiceTypeResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServiceTypeResponseBuilder toBuilder() =>
      ServiceTypeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServiceTypeResponse &&
        id == other.id &&
        categoryId == other.categoryId &&
        nameUk == other.nameUk &&
        nameEn == other.nameEn &&
        slug == other.slug;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, nameUk.hashCode);
    _$hash = $jc(_$hash, nameEn.hashCode);
    _$hash = $jc(_$hash, slug.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServiceTypeResponse')
          ..add('id', id)
          ..add('categoryId', categoryId)
          ..add('nameUk', nameUk)
          ..add('nameEn', nameEn)
          ..add('slug', slug))
        .toString();
  }
}

class ServiceTypeResponseBuilder
    implements Builder<ServiceTypeResponse, ServiceTypeResponseBuilder> {
  _$ServiceTypeResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _nameUk;
  String? get nameUk => _$this._nameUk;
  set nameUk(String? nameUk) => _$this._nameUk = nameUk;

  String? _nameEn;
  String? get nameEn => _$this._nameEn;
  set nameEn(String? nameEn) => _$this._nameEn = nameEn;

  String? _slug;
  String? get slug => _$this._slug;
  set slug(String? slug) => _$this._slug = slug;

  ServiceTypeResponseBuilder() {
    ServiceTypeResponse._defaults(this);
  }

  ServiceTypeResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _categoryId = $v.categoryId;
      _nameUk = $v.nameUk;
      _nameEn = $v.nameEn;
      _slug = $v.slug;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServiceTypeResponse other) {
    _$v = other as _$ServiceTypeResponse;
  }

  @override
  void update(void Function(ServiceTypeResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServiceTypeResponse build() => _build();

  _$ServiceTypeResponse _build() {
    final _$result = _$v ??
        _$ServiceTypeResponse._(
          id: id,
          categoryId: categoryId,
          nameUk: nameUk,
          nameEn: nameEn,
          slug: slug,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
