// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assign_service_to_master_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AssignServiceToMasterRequestPriceTypeEnum
    _$assignServiceToMasterRequestPriceTypeEnum_FIXED =
    const AssignServiceToMasterRequestPriceTypeEnum._('FIXED');
const AssignServiceToMasterRequestPriceTypeEnum
    _$assignServiceToMasterRequestPriceTypeEnum_RANGE =
    const AssignServiceToMasterRequestPriceTypeEnum._('RANGE');

AssignServiceToMasterRequestPriceTypeEnum
    _$assignServiceToMasterRequestPriceTypeEnumValueOf(String name) {
  switch (name) {
    case 'FIXED':
      return _$assignServiceToMasterRequestPriceTypeEnum_FIXED;
    case 'RANGE':
      return _$assignServiceToMasterRequestPriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AssignServiceToMasterRequestPriceTypeEnum>
    _$assignServiceToMasterRequestPriceTypeEnumValues = BuiltSet<
        AssignServiceToMasterRequestPriceTypeEnum>(const <AssignServiceToMasterRequestPriceTypeEnum>[
  _$assignServiceToMasterRequestPriceTypeEnum_FIXED,
  _$assignServiceToMasterRequestPriceTypeEnum_RANGE,
]);

Serializer<AssignServiceToMasterRequestPriceTypeEnum>
    _$assignServiceToMasterRequestPriceTypeEnumSerializer =
    _$AssignServiceToMasterRequestPriceTypeEnumSerializer();

class _$AssignServiceToMasterRequestPriceTypeEnumSerializer
    implements PrimitiveSerializer<AssignServiceToMasterRequestPriceTypeEnum> {
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
    AssignServiceToMasterRequestPriceTypeEnum
  ];
  @override
  final String wireName = 'AssignServiceToMasterRequestPriceTypeEnum';

  @override
  Object serialize(Serializers serializers,
          AssignServiceToMasterRequestPriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AssignServiceToMasterRequestPriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AssignServiceToMasterRequestPriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AssignServiceToMasterRequest extends AssignServiceToMasterRequest {
  @override
  final String serviceDefId;
  @override
  final AssignServiceToMasterRequestPriceTypeEnum? priceType;
  @override
  final num? priceOverride;
  @override
  final num? priceMax;
  @override
  final int? durationOverrideMinutes;
  @override
  final bool? bandLegal;

  factory _$AssignServiceToMasterRequest(
          [void Function(AssignServiceToMasterRequestBuilder)? updates]) =>
      (AssignServiceToMasterRequestBuilder()..update(updates))._build();

  _$AssignServiceToMasterRequest._(
      {required this.serviceDefId,
      this.priceType,
      this.priceOverride,
      this.priceMax,
      this.durationOverrideMinutes,
      this.bandLegal})
      : super._();
  @override
  AssignServiceToMasterRequest rebuild(
          void Function(AssignServiceToMasterRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AssignServiceToMasterRequestBuilder toBuilder() =>
      AssignServiceToMasterRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AssignServiceToMasterRequest &&
        serviceDefId == other.serviceDefId &&
        priceType == other.priceType &&
        priceOverride == other.priceOverride &&
        priceMax == other.priceMax &&
        durationOverrideMinutes == other.durationOverrideMinutes &&
        bandLegal == other.bandLegal;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, serviceDefId.hashCode);
    _$hash = $jc(_$hash, priceType.hashCode);
    _$hash = $jc(_$hash, priceOverride.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jc(_$hash, durationOverrideMinutes.hashCode);
    _$hash = $jc(_$hash, bandLegal.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AssignServiceToMasterRequest')
          ..add('serviceDefId', serviceDefId)
          ..add('priceType', priceType)
          ..add('priceOverride', priceOverride)
          ..add('priceMax', priceMax)
          ..add('durationOverrideMinutes', durationOverrideMinutes)
          ..add('bandLegal', bandLegal))
        .toString();
  }
}

class AssignServiceToMasterRequestBuilder
    implements
        Builder<AssignServiceToMasterRequest,
            AssignServiceToMasterRequestBuilder> {
  _$AssignServiceToMasterRequest? _$v;

  String? _serviceDefId;
  String? get serviceDefId => _$this._serviceDefId;
  set serviceDefId(String? serviceDefId) => _$this._serviceDefId = serviceDefId;

  AssignServiceToMasterRequestPriceTypeEnum? _priceType;
  AssignServiceToMasterRequestPriceTypeEnum? get priceType => _$this._priceType;
  set priceType(AssignServiceToMasterRequestPriceTypeEnum? priceType) =>
      _$this._priceType = priceType;

  num? _priceOverride;
  num? get priceOverride => _$this._priceOverride;
  set priceOverride(num? priceOverride) =>
      _$this._priceOverride = priceOverride;

  num? _priceMax;
  num? get priceMax => _$this._priceMax;
  set priceMax(num? priceMax) => _$this._priceMax = priceMax;

  int? _durationOverrideMinutes;
  int? get durationOverrideMinutes => _$this._durationOverrideMinutes;
  set durationOverrideMinutes(int? durationOverrideMinutes) =>
      _$this._durationOverrideMinutes = durationOverrideMinutes;

  bool? _bandLegal;
  bool? get bandLegal => _$this._bandLegal;
  set bandLegal(bool? bandLegal) => _$this._bandLegal = bandLegal;

  AssignServiceToMasterRequestBuilder() {
    AssignServiceToMasterRequest._defaults(this);
  }

  AssignServiceToMasterRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _serviceDefId = $v.serviceDefId;
      _priceType = $v.priceType;
      _priceOverride = $v.priceOverride;
      _priceMax = $v.priceMax;
      _durationOverrideMinutes = $v.durationOverrideMinutes;
      _bandLegal = $v.bandLegal;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AssignServiceToMasterRequest other) {
    _$v = other as _$AssignServiceToMasterRequest;
  }

  @override
  void update(void Function(AssignServiceToMasterRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AssignServiceToMasterRequest build() => _build();

  _$AssignServiceToMasterRequest _build() {
    final _$result = _$v ??
        _$AssignServiceToMasterRequest._(
          serviceDefId: BuiltValueNullFieldError.checkNotNull(
              serviceDefId, r'AssignServiceToMasterRequest', 'serviceDefId'),
          priceType: priceType,
          priceOverride: priceOverride,
          priceMax: priceMax,
          durationOverrideMinutes: durationOverrideMinutes,
          bandLegal: bandLegal,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
