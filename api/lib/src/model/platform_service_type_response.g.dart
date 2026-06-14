// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'platform_service_type_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlatformServiceTypeResponse extends PlatformServiceTypeResponse {
  @override
  final String? id;
  @override
  final String? slug;
  @override
  final String? nameUk;
  @override
  final String? categoryName;

  factory _$PlatformServiceTypeResponse(
          [void Function(PlatformServiceTypeResponseBuilder)? updates]) =>
      (PlatformServiceTypeResponseBuilder()..update(updates))._build();

  _$PlatformServiceTypeResponse._(
      {this.id, this.slug, this.nameUk, this.categoryName})
      : super._();
  @override
  PlatformServiceTypeResponse rebuild(
          void Function(PlatformServiceTypeResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlatformServiceTypeResponseBuilder toBuilder() =>
      PlatformServiceTypeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlatformServiceTypeResponse &&
        id == other.id &&
        slug == other.slug &&
        nameUk == other.nameUk &&
        categoryName == other.categoryName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, slug.hashCode);
    _$hash = $jc(_$hash, nameUk.hashCode);
    _$hash = $jc(_$hash, categoryName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlatformServiceTypeResponse')
          ..add('id', id)
          ..add('slug', slug)
          ..add('nameUk', nameUk)
          ..add('categoryName', categoryName))
        .toString();
  }
}

class PlatformServiceTypeResponseBuilder
    implements
        Builder<PlatformServiceTypeResponse,
            PlatformServiceTypeResponseBuilder> {
  _$PlatformServiceTypeResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _slug;
  String? get slug => _$this._slug;
  set slug(String? slug) => _$this._slug = slug;

  String? _nameUk;
  String? get nameUk => _$this._nameUk;
  set nameUk(String? nameUk) => _$this._nameUk = nameUk;

  String? _categoryName;
  String? get categoryName => _$this._categoryName;
  set categoryName(String? categoryName) => _$this._categoryName = categoryName;

  PlatformServiceTypeResponseBuilder() {
    PlatformServiceTypeResponse._defaults(this);
  }

  PlatformServiceTypeResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _slug = $v.slug;
      _nameUk = $v.nameUk;
      _categoryName = $v.categoryName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlatformServiceTypeResponse other) {
    _$v = other as _$PlatformServiceTypeResponse;
  }

  @override
  void update(void Function(PlatformServiceTypeResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlatformServiceTypeResponse build() => _build();

  _$PlatformServiceTypeResponse _build() {
    final _$result = _$v ??
        _$PlatformServiceTypeResponse._(
          id: id,
          slug: slug,
          nameUk: nameUk,
          categoryName: categoryName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
