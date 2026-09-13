// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_master_service_band_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UpdateMasterServiceBandRequestPriceTypeEnum
    _$updateMasterServiceBandRequestPriceTypeEnum_FIXED =
    const UpdateMasterServiceBandRequestPriceTypeEnum._('FIXED');
const UpdateMasterServiceBandRequestPriceTypeEnum
    _$updateMasterServiceBandRequestPriceTypeEnum_RANGE =
    const UpdateMasterServiceBandRequestPriceTypeEnum._('RANGE');

UpdateMasterServiceBandRequestPriceTypeEnum
    _$updateMasterServiceBandRequestPriceTypeEnumValueOf(String name) {
  switch (name) {
    case 'FIXED':
      return _$updateMasterServiceBandRequestPriceTypeEnum_FIXED;
    case 'RANGE':
      return _$updateMasterServiceBandRequestPriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<UpdateMasterServiceBandRequestPriceTypeEnum>
    _$updateMasterServiceBandRequestPriceTypeEnumValues = BuiltSet<
        UpdateMasterServiceBandRequestPriceTypeEnum>(const <UpdateMasterServiceBandRequestPriceTypeEnum>[
  _$updateMasterServiceBandRequestPriceTypeEnum_FIXED,
  _$updateMasterServiceBandRequestPriceTypeEnum_RANGE,
]);

Serializer<UpdateMasterServiceBandRequestPriceTypeEnum>
    _$updateMasterServiceBandRequestPriceTypeEnumSerializer =
    _$UpdateMasterServiceBandRequestPriceTypeEnumSerializer();

class _$UpdateMasterServiceBandRequestPriceTypeEnumSerializer
    implements
        PrimitiveSerializer<UpdateMasterServiceBandRequestPriceTypeEnum> {
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
    UpdateMasterServiceBandRequestPriceTypeEnum
  ];
  @override
  final String wireName = 'UpdateMasterServiceBandRequestPriceTypeEnum';

  @override
  Object serialize(Serializers serializers,
          UpdateMasterServiceBandRequestPriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  UpdateMasterServiceBandRequestPriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      UpdateMasterServiceBandRequestPriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$UpdateMasterServiceBandRequest extends UpdateMasterServiceBandRequest {
  @override
  final UpdateMasterServiceBandRequestPriceTypeEnum? priceType;
  @override
  final num? price;
  @override
  final num? priceMax;
  @override
  final int? durationOverrideMinutes;
  @override
  final bool? clearBand;
  @override
  final bool? clearDurationOverride;
  @override
  final bool? notEmpty;
  @override
  final bool? clearBandCoherent;
  @override
  final bool? clearDurationOverrideCoherent;
  @override
  final bool? bandLegal;

  factory _$UpdateMasterServiceBandRequest(
          [void Function(UpdateMasterServiceBandRequestBuilder)? updates]) =>
      (UpdateMasterServiceBandRequestBuilder()..update(updates))._build();

  _$UpdateMasterServiceBandRequest._(
      {this.priceType,
      this.price,
      this.priceMax,
      this.durationOverrideMinutes,
      this.clearBand,
      this.clearDurationOverride,
      this.notEmpty,
      this.clearBandCoherent,
      this.clearDurationOverrideCoherent,
      this.bandLegal})
      : super._();
  @override
  UpdateMasterServiceBandRequest rebuild(
          void Function(UpdateMasterServiceBandRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateMasterServiceBandRequestBuilder toBuilder() =>
      UpdateMasterServiceBandRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateMasterServiceBandRequest &&
        priceType == other.priceType &&
        price == other.price &&
        priceMax == other.priceMax &&
        durationOverrideMinutes == other.durationOverrideMinutes &&
        clearBand == other.clearBand &&
        clearDurationOverride == other.clearDurationOverride &&
        notEmpty == other.notEmpty &&
        clearBandCoherent == other.clearBandCoherent &&
        clearDurationOverrideCoherent == other.clearDurationOverrideCoherent &&
        bandLegal == other.bandLegal;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, priceType.hashCode);
    _$hash = $jc(_$hash, price.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jc(_$hash, durationOverrideMinutes.hashCode);
    _$hash = $jc(_$hash, clearBand.hashCode);
    _$hash = $jc(_$hash, clearDurationOverride.hashCode);
    _$hash = $jc(_$hash, notEmpty.hashCode);
    _$hash = $jc(_$hash, clearBandCoherent.hashCode);
    _$hash = $jc(_$hash, clearDurationOverrideCoherent.hashCode);
    _$hash = $jc(_$hash, bandLegal.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateMasterServiceBandRequest')
          ..add('priceType', priceType)
          ..add('price', price)
          ..add('priceMax', priceMax)
          ..add('durationOverrideMinutes', durationOverrideMinutes)
          ..add('clearBand', clearBand)
          ..add('clearDurationOverride', clearDurationOverride)
          ..add('notEmpty', notEmpty)
          ..add('clearBandCoherent', clearBandCoherent)
          ..add('clearDurationOverrideCoherent', clearDurationOverrideCoherent)
          ..add('bandLegal', bandLegal))
        .toString();
  }
}

class UpdateMasterServiceBandRequestBuilder
    implements
        Builder<UpdateMasterServiceBandRequest,
            UpdateMasterServiceBandRequestBuilder> {
  _$UpdateMasterServiceBandRequest? _$v;

  UpdateMasterServiceBandRequestPriceTypeEnum? _priceType;
  UpdateMasterServiceBandRequestPriceTypeEnum? get priceType =>
      _$this._priceType;
  set priceType(UpdateMasterServiceBandRequestPriceTypeEnum? priceType) =>
      _$this._priceType = priceType;

  num? _price;
  num? get price => _$this._price;
  set price(num? price) => _$this._price = price;

  num? _priceMax;
  num? get priceMax => _$this._priceMax;
  set priceMax(num? priceMax) => _$this._priceMax = priceMax;

  int? _durationOverrideMinutes;
  int? get durationOverrideMinutes => _$this._durationOverrideMinutes;
  set durationOverrideMinutes(int? durationOverrideMinutes) =>
      _$this._durationOverrideMinutes = durationOverrideMinutes;

  bool? _clearBand;
  bool? get clearBand => _$this._clearBand;
  set clearBand(bool? clearBand) => _$this._clearBand = clearBand;

  bool? _clearDurationOverride;
  bool? get clearDurationOverride => _$this._clearDurationOverride;
  set clearDurationOverride(bool? clearDurationOverride) =>
      _$this._clearDurationOverride = clearDurationOverride;

  bool? _notEmpty;
  bool? get notEmpty => _$this._notEmpty;
  set notEmpty(bool? notEmpty) => _$this._notEmpty = notEmpty;

  bool? _clearBandCoherent;
  bool? get clearBandCoherent => _$this._clearBandCoherent;
  set clearBandCoherent(bool? clearBandCoherent) =>
      _$this._clearBandCoherent = clearBandCoherent;

  bool? _clearDurationOverrideCoherent;
  bool? get clearDurationOverrideCoherent =>
      _$this._clearDurationOverrideCoherent;
  set clearDurationOverrideCoherent(bool? clearDurationOverrideCoherent) =>
      _$this._clearDurationOverrideCoherent = clearDurationOverrideCoherent;

  bool? _bandLegal;
  bool? get bandLegal => _$this._bandLegal;
  set bandLegal(bool? bandLegal) => _$this._bandLegal = bandLegal;

  UpdateMasterServiceBandRequestBuilder() {
    UpdateMasterServiceBandRequest._defaults(this);
  }

  UpdateMasterServiceBandRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _priceType = $v.priceType;
      _price = $v.price;
      _priceMax = $v.priceMax;
      _durationOverrideMinutes = $v.durationOverrideMinutes;
      _clearBand = $v.clearBand;
      _clearDurationOverride = $v.clearDurationOverride;
      _notEmpty = $v.notEmpty;
      _clearBandCoherent = $v.clearBandCoherent;
      _clearDurationOverrideCoherent = $v.clearDurationOverrideCoherent;
      _bandLegal = $v.bandLegal;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateMasterServiceBandRequest other) {
    _$v = other as _$UpdateMasterServiceBandRequest;
  }

  @override
  void update(void Function(UpdateMasterServiceBandRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateMasterServiceBandRequest build() => _build();

  _$UpdateMasterServiceBandRequest _build() {
    final _$result = _$v ??
        _$UpdateMasterServiceBandRequest._(
          priceType: priceType,
          price: price,
          priceMax: priceMax,
          durationOverrideMinutes: durationOverrideMinutes,
          clearBand: clearBand,
          clearDurationOverride: clearDurationOverride,
          notEmpty: notEmpty,
          clearBandCoherent: clearBandCoherent,
          clearDurationOverrideCoherent: clearDurationOverrideCoherent,
          bandLegal: bandLegal,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
