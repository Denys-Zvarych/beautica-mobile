// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_search_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SalonSearchRequestSortEnum _$salonSearchRequestSortEnum_RATING_DESC =
    const SalonSearchRequestSortEnum._('RATING_DESC');
const SalonSearchRequestSortEnum _$salonSearchRequestSortEnum_PRICE_ASC =
    const SalonSearchRequestSortEnum._('PRICE_ASC');
const SalonSearchRequestSortEnum _$salonSearchRequestSortEnum_PRICE_DESC =
    const SalonSearchRequestSortEnum._('PRICE_DESC');
const SalonSearchRequestSortEnum _$salonSearchRequestSortEnum_REVIEWS_DESC =
    const SalonSearchRequestSortEnum._('REVIEWS_DESC');

SalonSearchRequestSortEnum _$salonSearchRequestSortEnumValueOf(String name) {
  switch (name) {
    case 'RATING_DESC':
      return _$salonSearchRequestSortEnum_RATING_DESC;
    case 'PRICE_ASC':
      return _$salonSearchRequestSortEnum_PRICE_ASC;
    case 'PRICE_DESC':
      return _$salonSearchRequestSortEnum_PRICE_DESC;
    case 'REVIEWS_DESC':
      return _$salonSearchRequestSortEnum_REVIEWS_DESC;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<SalonSearchRequestSortEnum> _$salonSearchRequestSortEnumValues =
    BuiltSet<SalonSearchRequestSortEnum>(const <SalonSearchRequestSortEnum>[
  _$salonSearchRequestSortEnum_RATING_DESC,
  _$salonSearchRequestSortEnum_PRICE_ASC,
  _$salonSearchRequestSortEnum_PRICE_DESC,
  _$salonSearchRequestSortEnum_REVIEWS_DESC,
]);

Serializer<SalonSearchRequestSortEnum> _$salonSearchRequestSortEnumSerializer =
    _$SalonSearchRequestSortEnumSerializer();

class _$SalonSearchRequestSortEnumSerializer
    implements PrimitiveSerializer<SalonSearchRequestSortEnum> {
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
  final Iterable<Type> types = const <Type>[SalonSearchRequestSortEnum];
  @override
  final String wireName = 'SalonSearchRequestSortEnum';

  @override
  Object serialize(Serializers serializers, SalonSearchRequestSortEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  SalonSearchRequestSortEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      SalonSearchRequestSortEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$SalonSearchRequest extends SalonSearchRequest {
  @override
  final LocationFilter? location;
  @override
  final String? q;
  @override
  final String? category;
  @override
  final SalonSearchRequestSortEnum? sort;
  @override
  final num? minPrice;
  @override
  final num? maxPrice;
  @override
  final int? page;
  @override
  final int? size;
  @override
  final BuiltList<String>? serviceTypeSlugs;
  @override
  final bool? priceRangeValid;
  @override
  final bool? withinResultWindow;

  factory _$SalonSearchRequest(
          [void Function(SalonSearchRequestBuilder)? updates]) =>
      (SalonSearchRequestBuilder()..update(updates))._build();

  _$SalonSearchRequest._(
      {this.location,
      this.q,
      this.category,
      this.sort,
      this.minPrice,
      this.maxPrice,
      this.page,
      this.size,
      this.serviceTypeSlugs,
      this.priceRangeValid,
      this.withinResultWindow})
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
        q == other.q &&
        category == other.category &&
        sort == other.sort &&
        minPrice == other.minPrice &&
        maxPrice == other.maxPrice &&
        page == other.page &&
        size == other.size &&
        serviceTypeSlugs == other.serviceTypeSlugs &&
        priceRangeValid == other.priceRangeValid &&
        withinResultWindow == other.withinResultWindow;
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
    _$hash = $jc(_$hash, page.hashCode);
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jc(_$hash, serviceTypeSlugs.hashCode);
    _$hash = $jc(_$hash, priceRangeValid.hashCode);
    _$hash = $jc(_$hash, withinResultWindow.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonSearchRequest')
          ..add('location', location)
          ..add('q', q)
          ..add('category', category)
          ..add('sort', sort)
          ..add('minPrice', minPrice)
          ..add('maxPrice', maxPrice)
          ..add('page', page)
          ..add('size', size)
          ..add('serviceTypeSlugs', serviceTypeSlugs)
          ..add('priceRangeValid', priceRangeValid)
          ..add('withinResultWindow', withinResultWindow))
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

  String? _q;
  String? get q => _$this._q;
  set q(String? q) => _$this._q = q;

  String? _category;
  String? get category => _$this._category;
  set category(String? category) => _$this._category = category;

  SalonSearchRequestSortEnum? _sort;
  SalonSearchRequestSortEnum? get sort => _$this._sort;
  set sort(SalonSearchRequestSortEnum? sort) => _$this._sort = sort;

  num? _minPrice;
  num? get minPrice => _$this._minPrice;
  set minPrice(num? minPrice) => _$this._minPrice = minPrice;

  num? _maxPrice;
  num? get maxPrice => _$this._maxPrice;
  set maxPrice(num? maxPrice) => _$this._maxPrice = maxPrice;

  int? _page;
  int? get page => _$this._page;
  set page(int? page) => _$this._page = page;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  ListBuilder<String>? _serviceTypeSlugs;
  ListBuilder<String> get serviceTypeSlugs =>
      _$this._serviceTypeSlugs ??= ListBuilder<String>();
  set serviceTypeSlugs(ListBuilder<String>? serviceTypeSlugs) =>
      _$this._serviceTypeSlugs = serviceTypeSlugs;

  bool? _priceRangeValid;
  bool? get priceRangeValid => _$this._priceRangeValid;
  set priceRangeValid(bool? priceRangeValid) =>
      _$this._priceRangeValid = priceRangeValid;

  bool? _withinResultWindow;
  bool? get withinResultWindow => _$this._withinResultWindow;
  set withinResultWindow(bool? withinResultWindow) =>
      _$this._withinResultWindow = withinResultWindow;

  SalonSearchRequestBuilder() {
    SalonSearchRequest._defaults(this);
  }

  SalonSearchRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _location = $v.location?.toBuilder();
      _q = $v.q;
      _category = $v.category;
      _sort = $v.sort;
      _minPrice = $v.minPrice;
      _maxPrice = $v.maxPrice;
      _page = $v.page;
      _size = $v.size;
      _serviceTypeSlugs = $v.serviceTypeSlugs?.toBuilder();
      _priceRangeValid = $v.priceRangeValid;
      _withinResultWindow = $v.withinResultWindow;
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
            q: q,
            category: category,
            sort: sort,
            minPrice: minPrice,
            maxPrice: maxPrice,
            page: page,
            size: size,
            serviceTypeSlugs: _serviceTypeSlugs?.build(),
            priceRangeValid: priceRangeValid,
            withinResultWindow: withinResultWindow,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'location';
        _location?.build();

        _$failedField = 'serviceTypeSlugs';
        _serviceTypeSlugs?.build();
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
