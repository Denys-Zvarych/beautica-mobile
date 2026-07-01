// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_service_catalog_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonServiceCatalogResponse extends SalonServiceCatalogResponse {
  @override
  final BuiltList<SalonServiceCategoryGroup>? categories;

  factory _$SalonServiceCatalogResponse(
          [void Function(SalonServiceCatalogResponseBuilder)? updates]) =>
      (SalonServiceCatalogResponseBuilder()..update(updates))._build();

  _$SalonServiceCatalogResponse._({this.categories}) : super._();
  @override
  SalonServiceCatalogResponse rebuild(
          void Function(SalonServiceCatalogResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonServiceCatalogResponseBuilder toBuilder() =>
      SalonServiceCatalogResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonServiceCatalogResponse &&
        categories == other.categories;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categories.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonServiceCatalogResponse')
          ..add('categories', categories))
        .toString();
  }
}

class SalonServiceCatalogResponseBuilder
    implements
        Builder<SalonServiceCatalogResponse,
            SalonServiceCatalogResponseBuilder> {
  _$SalonServiceCatalogResponse? _$v;

  ListBuilder<SalonServiceCategoryGroup>? _categories;
  ListBuilder<SalonServiceCategoryGroup> get categories =>
      _$this._categories ??= ListBuilder<SalonServiceCategoryGroup>();
  set categories(ListBuilder<SalonServiceCategoryGroup>? categories) =>
      _$this._categories = categories;

  SalonServiceCatalogResponseBuilder() {
    SalonServiceCatalogResponse._defaults(this);
  }

  SalonServiceCatalogResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categories = $v.categories?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonServiceCatalogResponse other) {
    _$v = other as _$SalonServiceCatalogResponse;
  }

  @override
  void update(void Function(SalonServiceCatalogResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonServiceCatalogResponse build() => _build();

  _$SalonServiceCatalogResponse _build() {
    _$SalonServiceCatalogResponse _$result;
    try {
      _$result = _$v ??
          _$SalonServiceCatalogResponse._(
            categories: _categories?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'categories';
        _categories?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonServiceCatalogResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
