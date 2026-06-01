// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_search_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MasterSearchRequest extends MasterSearchRequest {
  @override
  final LocationFilter? location;
  @override
  final String? category;
  @override
  final num? minPrice;
  @override
  final num? maxPrice;
  @override
  final num? minRating;
  @override
  final int? page;
  @override
  final int? size;
  @override
  final bool? priceRangeValid;

  factory _$MasterSearchRequest(
          [void Function(MasterSearchRequestBuilder)? updates]) =>
      (MasterSearchRequestBuilder()..update(updates))._build();

  _$MasterSearchRequest._(
      {this.location,
      this.category,
      this.minPrice,
      this.maxPrice,
      this.minRating,
      this.page,
      this.size,
      this.priceRangeValid})
      : super._();
  @override
  MasterSearchRequest rebuild(
          void Function(MasterSearchRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterSearchRequestBuilder toBuilder() =>
      MasterSearchRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterSearchRequest &&
        location == other.location &&
        category == other.category &&
        minPrice == other.minPrice &&
        maxPrice == other.maxPrice &&
        minRating == other.minRating &&
        page == other.page &&
        size == other.size &&
        priceRangeValid == other.priceRangeValid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, minPrice.hashCode);
    _$hash = $jc(_$hash, maxPrice.hashCode);
    _$hash = $jc(_$hash, minRating.hashCode);
    _$hash = $jc(_$hash, page.hashCode);
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jc(_$hash, priceRangeValid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterSearchRequest')
          ..add('location', location)
          ..add('category', category)
          ..add('minPrice', minPrice)
          ..add('maxPrice', maxPrice)
          ..add('minRating', minRating)
          ..add('page', page)
          ..add('size', size)
          ..add('priceRangeValid', priceRangeValid))
        .toString();
  }
}

class MasterSearchRequestBuilder
    implements Builder<MasterSearchRequest, MasterSearchRequestBuilder> {
  _$MasterSearchRequest? _$v;

  LocationFilterBuilder? _location;
  LocationFilterBuilder get location =>
      _$this._location ??= LocationFilterBuilder();
  set location(LocationFilterBuilder? location) => _$this._location = location;

  String? _category;
  String? get category => _$this._category;
  set category(String? category) => _$this._category = category;

  num? _minPrice;
  num? get minPrice => _$this._minPrice;
  set minPrice(num? minPrice) => _$this._minPrice = minPrice;

  num? _maxPrice;
  num? get maxPrice => _$this._maxPrice;
  set maxPrice(num? maxPrice) => _$this._maxPrice = maxPrice;

  num? _minRating;
  num? get minRating => _$this._minRating;
  set minRating(num? minRating) => _$this._minRating = minRating;

  int? _page;
  int? get page => _$this._page;
  set page(int? page) => _$this._page = page;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  bool? _priceRangeValid;
  bool? get priceRangeValid => _$this._priceRangeValid;
  set priceRangeValid(bool? priceRangeValid) =>
      _$this._priceRangeValid = priceRangeValid;

  MasterSearchRequestBuilder() {
    MasterSearchRequest._defaults(this);
  }

  MasterSearchRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _location = $v.location?.toBuilder();
      _category = $v.category;
      _minPrice = $v.minPrice;
      _maxPrice = $v.maxPrice;
      _minRating = $v.minRating;
      _page = $v.page;
      _size = $v.size;
      _priceRangeValid = $v.priceRangeValid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MasterSearchRequest other) {
    _$v = other as _$MasterSearchRequest;
  }

  @override
  void update(void Function(MasterSearchRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterSearchRequest build() => _build();

  _$MasterSearchRequest _build() {
    _$MasterSearchRequest _$result;
    try {
      _$result = _$v ??
          _$MasterSearchRequest._(
            location: _location?.build(),
            category: category,
            minPrice: minPrice,
            maxPrice: maxPrice,
            minRating: minRating,
            page: page,
            size: size,
            priceRangeValid: priceRangeValid,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'location';
        _location?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MasterSearchRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
