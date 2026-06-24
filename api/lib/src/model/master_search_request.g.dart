// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_search_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MasterSearchRequestSortEnum _$masterSearchRequestSortEnum_RATING_DESC =
    const MasterSearchRequestSortEnum._('RATING_DESC');
const MasterSearchRequestSortEnum _$masterSearchRequestSortEnum_PRICE_ASC =
    const MasterSearchRequestSortEnum._('PRICE_ASC');
const MasterSearchRequestSortEnum _$masterSearchRequestSortEnum_PRICE_DESC =
    const MasterSearchRequestSortEnum._('PRICE_DESC');
const MasterSearchRequestSortEnum _$masterSearchRequestSortEnum_REVIEWS_DESC =
    const MasterSearchRequestSortEnum._('REVIEWS_DESC');

MasterSearchRequestSortEnum _$masterSearchRequestSortEnumValueOf(String name) {
  switch (name) {
    case 'RATING_DESC':
      return _$masterSearchRequestSortEnum_RATING_DESC;
    case 'PRICE_ASC':
      return _$masterSearchRequestSortEnum_PRICE_ASC;
    case 'PRICE_DESC':
      return _$masterSearchRequestSortEnum_PRICE_DESC;
    case 'REVIEWS_DESC':
      return _$masterSearchRequestSortEnum_REVIEWS_DESC;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MasterSearchRequestSortEnum>
    _$masterSearchRequestSortEnumValues =
    BuiltSet<MasterSearchRequestSortEnum>(const <MasterSearchRequestSortEnum>[
  _$masterSearchRequestSortEnum_RATING_DESC,
  _$masterSearchRequestSortEnum_PRICE_ASC,
  _$masterSearchRequestSortEnum_PRICE_DESC,
  _$masterSearchRequestSortEnum_REVIEWS_DESC,
]);

Serializer<MasterSearchRequestSortEnum>
    _$masterSearchRequestSortEnumSerializer =
    _$MasterSearchRequestSortEnumSerializer();

class _$MasterSearchRequestSortEnumSerializer
    implements PrimitiveSerializer<MasterSearchRequestSortEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'RATING_DESC': 'RATING_DESC',
    'PRICE_ASC': 'PRICE_ASC',
    'PRICE_DESC': 'PRICE_DESC',
    'REVIEWS_DESC': 'REVIEWS_DESC',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'RATING_DESC': 'RATING_DESC',
    'PRICE_ASC': 'PRICE_ASC',
    'PRICE_DESC': 'PRICE_DESC',
    'REVIEWS_DESC': 'REVIEWS_DESC',
  };

  @override
  final Iterable<Type> types = const <Type>[MasterSearchRequestSortEnum];
  @override
  final String wireName = 'MasterSearchRequestSortEnum';

  @override
  Object serialize(Serializers serializers, MasterSearchRequestSortEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MasterSearchRequestSortEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MasterSearchRequestSortEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$MasterSearchRequest extends MasterSearchRequest {
  @override
  final LocationFilter? location;
  @override
  final String? q;
  @override
  final String? category;
  @override
  final MasterSearchRequestSortEnum? sort;
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
      this.q,
      this.category,
      this.sort,
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
        q == other.q &&
        category == other.category &&
        sort == other.sort &&
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
    _$hash = $jc(_$hash, q.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, sort.hashCode);
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
          ..add('q', q)
          ..add('category', category)
          ..add('sort', sort)
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

  String? _q;
  String? get q => _$this._q;
  set q(String? q) => _$this._q = q;

  String? _category;
  String? get category => _$this._category;
  set category(String? category) => _$this._category = category;

  MasterSearchRequestSortEnum? _sort;
  MasterSearchRequestSortEnum? get sort => _$this._sort;
  set sort(MasterSearchRequestSortEnum? sort) => _$this._sort = sort;

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
      _q = $v.q;
      _category = $v.category;
      _sort = $v.sort;
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
            q: q,
            category: category,
            sort: sort,
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
