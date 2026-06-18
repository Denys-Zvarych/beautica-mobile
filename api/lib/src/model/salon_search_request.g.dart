// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_search_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonSearchRequest extends SalonSearchRequest {
  @override
  final LocationFilter? location;
  @override
  final String? category;
  @override
  final int? page;
  @override
  final int? size;

  factory _$SalonSearchRequest(
          [void Function(SalonSearchRequestBuilder)? updates]) =>
      (SalonSearchRequestBuilder()..update(updates))._build();

  _$SalonSearchRequest._({this.location, this.category, this.page, this.size})
      : super._();
  @override
  SalonSearchRequest rebuild(
          void Function(SalonSearchRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonSearchRequestBuilder toBuilder() =>
      SalonSearchRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonSearchRequest &&
        location == other.location &&
        category == other.category &&
        page == other.page &&
        size == other.size;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, page.hashCode);
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonSearchRequest')
          ..add('location', location)
          ..add('category', category)
          ..add('page', page)
          ..add('size', size))
        .toString();
  }
}

class SalonSearchRequestBuilder
    implements Builder<SalonSearchRequest, SalonSearchRequestBuilder> {
  _$SalonSearchRequest? _$v;

  LocationFilterBuilder? _location;
  LocationFilterBuilder get location =>
      _$this._location ??= LocationFilterBuilder();
  set location(LocationFilterBuilder? location) => _$this._location = location;

  String? _category;
  String? get category => _$this._category;
  set category(String? category) => _$this._category = category;

  int? _page;
  int? get page => _$this._page;
  set page(int? page) => _$this._page = page;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  SalonSearchRequestBuilder() {
    SalonSearchRequest._defaults(this);
  }

  SalonSearchRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _location = $v.location?.toBuilder();
      _category = $v.category;
      _page = $v.page;
      _size = $v.size;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonSearchRequest other) {
    _$v = other as _$SalonSearchRequest;
  }

  @override
  void update(void Function(SalonSearchRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonSearchRequest build() => _build();

  _$SalonSearchRequest _build() {
    _$SalonSearchRequest _$result;
    try {
      _$result = _$v ??
          _$SalonSearchRequest._(
            location: _location?.build(),
            category: category,
            page: page,
            size: size,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'location';
        _location?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonSearchRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
