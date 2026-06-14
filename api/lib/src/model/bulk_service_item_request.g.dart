// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bulk_service_item_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BulkServiceItemRequestPriceTypeEnum
    _$bulkServiceItemRequestPriceTypeEnum_FIXED =
    const BulkServiceItemRequestPriceTypeEnum._('FIXED');
const BulkServiceItemRequestPriceTypeEnum
    _$bulkServiceItemRequestPriceTypeEnum_RANGE =
    const BulkServiceItemRequestPriceTypeEnum._('RANGE');

BulkServiceItemRequestPriceTypeEnum
    _$bulkServiceItemRequestPriceTypeEnumValueOf(String name) {
  switch (name) {
    case 'FIXED':
      return _$bulkServiceItemRequestPriceTypeEnum_FIXED;
    case 'RANGE':
      return _$bulkServiceItemRequestPriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BulkServiceItemRequestPriceTypeEnum>
    _$bulkServiceItemRequestPriceTypeEnumValues = BuiltSet<
        BulkServiceItemRequestPriceTypeEnum>(const <BulkServiceItemRequestPriceTypeEnum>[
  _$bulkServiceItemRequestPriceTypeEnum_FIXED,
  _$bulkServiceItemRequestPriceTypeEnum_RANGE,
]);

Serializer<BulkServiceItemRequestPriceTypeEnum>
    _$bulkServiceItemRequestPriceTypeEnumSerializer =
    _$BulkServiceItemRequestPriceTypeEnumSerializer();

class _$BulkServiceItemRequestPriceTypeEnumSerializer
    implements PrimitiveSerializer<BulkServiceItemRequestPriceTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'FIXED': 'FIXED',
    'RANGE': 'RANGE',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'FIXED': 'FIXED',
    'RANGE': 'RANGE',
  };

  @override
  final Iterable<Type> types = const <Type>[
    BulkServiceItemRequestPriceTypeEnum
  ];
  @override
  final String wireName = 'BulkServiceItemRequestPriceTypeEnum';

  @override
  Object serialize(
          Serializers serializers, BulkServiceItemRequestPriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BulkServiceItemRequestPriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BulkServiceItemRequestPriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BulkServiceItemRequest extends BulkServiceItemRequest {
  @override
  final String serviceTypeId;
  @override
  final int durationMinutes;
  @override
  final BulkServiceItemRequestPriceTypeEnum priceType;
  @override
  final num? price;
  @override
  final num? priceMin;
  @override
  final num? priceMax;

  factory _$BulkServiceItemRequest(
          [void Function(BulkServiceItemRequestBuilder)? updates]) =>
      (BulkServiceItemRequestBuilder()..update(updates))._build();

  _$BulkServiceItemRequest._(
      {required this.serviceTypeId,
      required this.durationMinutes,
      required this.priceType,
      this.price,
      this.priceMin,
      this.priceMax})
      : super._();
  @override
  BulkServiceItemRequest rebuild(
          void Function(BulkServiceItemRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BulkServiceItemRequestBuilder toBuilder() =>
      BulkServiceItemRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BulkServiceItemRequest &&
        serviceTypeId == other.serviceTypeId &&
        durationMinutes == other.durationMinutes &&
        priceType == other.priceType &&
        price == other.price &&
        priceMin == other.priceMin &&
        priceMax == other.priceMax;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, serviceTypeId.hashCode);
    _$hash = $jc(_$hash, durationMinutes.hashCode);
    _$hash = $jc(_$hash, priceType.hashCode);
    _$hash = $jc(_$hash, price.hashCode);
    _$hash = $jc(_$hash, priceMin.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BulkServiceItemRequest')
          ..add('serviceTypeId', serviceTypeId)
          ..add('durationMinutes', durationMinutes)
          ..add('priceType', priceType)
          ..add('price', price)
          ..add('priceMin', priceMin)
          ..add('priceMax', priceMax))
        .toString();
  }
}

class BulkServiceItemRequestBuilder
    implements Builder<BulkServiceItemRequest, BulkServiceItemRequestBuilder> {
  _$BulkServiceItemRequest? _$v;

  String? _serviceTypeId;
  String? get serviceTypeId => _$this._serviceTypeId;
  set serviceTypeId(String? serviceTypeId) =>
      _$this._serviceTypeId = serviceTypeId;

  int? _durationMinutes;
  int? get durationMinutes => _$this._durationMinutes;
  set durationMinutes(int? durationMinutes) =>
      _$this._durationMinutes = durationMinutes;

  BulkServiceItemRequestPriceTypeEnum? _priceType;
  BulkServiceItemRequestPriceTypeEnum? get priceType => _$this._priceType;
  set priceType(BulkServiceItemRequestPriceTypeEnum? priceType) =>
      _$this._priceType = priceType;

  num? _price;
  num? get price => _$this._price;
  set price(num? price) => _$this._price = price;

  num? _priceMin;
  num? get priceMin => _$this._priceMin;
  set priceMin(num? priceMin) => _$this._priceMin = priceMin;

  num? _priceMax;
  num? get priceMax => _$this._priceMax;
  set priceMax(num? priceMax) => _$this._priceMax = priceMax;

  BulkServiceItemRequestBuilder() {
    BulkServiceItemRequest._defaults(this);
  }

  BulkServiceItemRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _serviceTypeId = $v.serviceTypeId;
      _durationMinutes = $v.durationMinutes;
      _priceType = $v.priceType;
      _price = $v.price;
      _priceMin = $v.priceMin;
      _priceMax = $v.priceMax;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BulkServiceItemRequest other) {
    _$v = other as _$BulkServiceItemRequest;
  }

  @override
  void update(void Function(BulkServiceItemRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BulkServiceItemRequest build() => _build();

  _$BulkServiceItemRequest _build() {
    final _$result = _$v ??
        _$BulkServiceItemRequest._(
          serviceTypeId: BuiltValueNullFieldError.checkNotNull(
              serviceTypeId, r'BulkServiceItemRequest', 'serviceTypeId'),
          durationMinutes: BuiltValueNullFieldError.checkNotNull(
              durationMinutes, r'BulkServiceItemRequest', 'durationMinutes'),
          priceType: BuiltValueNullFieldError.checkNotNull(
              priceType, r'BulkServiceItemRequest', 'priceType'),
          price: price,
          priceMin: priceMin,
          priceMax: priceMax,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
