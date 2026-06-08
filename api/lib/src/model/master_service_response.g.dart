// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_service_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MasterServiceResponsePriceTypeEnum
    _$masterServiceResponsePriceTypeEnum_FIXED =
    const MasterServiceResponsePriceTypeEnum._('FIXED');
const MasterServiceResponsePriceTypeEnum
    _$masterServiceResponsePriceTypeEnum_RANGE =
    const MasterServiceResponsePriceTypeEnum._('RANGE');

MasterServiceResponsePriceTypeEnum _$masterServiceResponsePriceTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'FIXED':
      return _$masterServiceResponsePriceTypeEnum_FIXED;
    case 'RANGE':
      return _$masterServiceResponsePriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MasterServiceResponsePriceTypeEnum>
    _$masterServiceResponsePriceTypeEnumValues = BuiltSet<
        MasterServiceResponsePriceTypeEnum>(const <MasterServiceResponsePriceTypeEnum>[
  _$masterServiceResponsePriceTypeEnum_FIXED,
  _$masterServiceResponsePriceTypeEnum_RANGE,
]);

Serializer<MasterServiceResponsePriceTypeEnum>
    _$masterServiceResponsePriceTypeEnumSerializer =
    _$MasterServiceResponsePriceTypeEnumSerializer();

class _$MasterServiceResponsePriceTypeEnumSerializer
    implements PrimitiveSerializer<MasterServiceResponsePriceTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'FIXED': 'FIXED',
    'RANGE': 'RANGE',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'FIXED': 'FIXED',
    'RANGE': 'RANGE',
  };

  @override
  final Iterable<Type> types = const <Type>[MasterServiceResponsePriceTypeEnum];
  @override
  final String wireName = 'MasterServiceResponsePriceTypeEnum';

  @override
  Object serialize(
          Serializers serializers, MasterServiceResponsePriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MasterServiceResponsePriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MasterServiceResponsePriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$MasterServiceResponse extends MasterServiceResponse {
  @override
  final String? id;
  @override
  final String? masterId;
  @override
  final ServiceDefinitionResponse? serviceDefinition;
  @override
  final num? priceOverride;
  @override
  final int? durationOverrideMinutes;
  @override
  final num? effectivePrice;
  @override
  final int? effectiveDurationMinutes;
  @override
  final bool? isActive;
  @override
  final MasterServiceResponsePriceTypeEnum? priceType;
  @override
  final num? priceMin;
  @override
  final num? priceMax;
  @override
  final String? priceDisplay;
  @override
  final String? serviceTypeId;
  @override
  final String? serviceTypeNameUk;
  @override
  final bool? isDraft;

  factory _$MasterServiceResponse(
          [void Function(MasterServiceResponseBuilder)? updates]) =>
      (MasterServiceResponseBuilder()..update(updates))._build();

  _$MasterServiceResponse._(
      {this.id,
      this.masterId,
      this.serviceDefinition,
      this.priceOverride,
      this.durationOverrideMinutes,
      this.effectivePrice,
      this.effectiveDurationMinutes,
      this.isActive,
      this.priceType,
      this.priceMin,
      this.priceMax,
      this.priceDisplay,
      this.serviceTypeId,
      this.serviceTypeNameUk,
      this.isDraft})
      : super._();
  @override
  MasterServiceResponse rebuild(
          void Function(MasterServiceResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterServiceResponseBuilder toBuilder() =>
      MasterServiceResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterServiceResponse &&
        id == other.id &&
        masterId == other.masterId &&
        serviceDefinition == other.serviceDefinition &&
        priceOverride == other.priceOverride &&
        durationOverrideMinutes == other.durationOverrideMinutes &&
        effectivePrice == other.effectivePrice &&
        effectiveDurationMinutes == other.effectiveDurationMinutes &&
        isActive == other.isActive &&
        priceType == other.priceType &&
        priceMin == other.priceMin &&
        priceMax == other.priceMax &&
        priceDisplay == other.priceDisplay &&
        serviceTypeId == other.serviceTypeId &&
        serviceTypeNameUk == other.serviceTypeNameUk &&
        isDraft == other.isDraft;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, serviceDefinition.hashCode);
    _$hash = $jc(_$hash, priceOverride.hashCode);
    _$hash = $jc(_$hash, durationOverrideMinutes.hashCode);
    _$hash = $jc(_$hash, effectivePrice.hashCode);
    _$hash = $jc(_$hash, effectiveDurationMinutes.hashCode);
    _$hash = $jc(_$hash, isActive.hashCode);
    _$hash = $jc(_$hash, priceType.hashCode);
    _$hash = $jc(_$hash, priceMin.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jc(_$hash, priceDisplay.hashCode);
    _$hash = $jc(_$hash, serviceTypeId.hashCode);
    _$hash = $jc(_$hash, serviceTypeNameUk.hashCode);
    _$hash = $jc(_$hash, isDraft.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterServiceResponse')
          ..add('id', id)
          ..add('masterId', masterId)
          ..add('serviceDefinition', serviceDefinition)
          ..add('priceOverride', priceOverride)
          ..add('durationOverrideMinutes', durationOverrideMinutes)
          ..add('effectivePrice', effectivePrice)
          ..add('effectiveDurationMinutes', effectiveDurationMinutes)
          ..add('isActive', isActive)
          ..add('priceType', priceType)
          ..add('priceMin', priceMin)
          ..add('priceMax', priceMax)
          ..add('priceDisplay', priceDisplay)
          ..add('serviceTypeId', serviceTypeId)
          ..add('serviceTypeNameUk', serviceTypeNameUk)
          ..add('isDraft', isDraft))
        .toString();
  }
}

class MasterServiceResponseBuilder
    implements Builder<MasterServiceResponse, MasterServiceResponseBuilder> {
  _$MasterServiceResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  ServiceDefinitionResponseBuilder? _serviceDefinition;
  ServiceDefinitionResponseBuilder get serviceDefinition =>
      _$this._serviceDefinition ??= ServiceDefinitionResponseBuilder();
  set serviceDefinition(ServiceDefinitionResponseBuilder? serviceDefinition) =>
      _$this._serviceDefinition = serviceDefinition;

  num? _priceOverride;
  num? get priceOverride => _$this._priceOverride;
  set priceOverride(num? priceOverride) =>
      _$this._priceOverride = priceOverride;

  int? _durationOverrideMinutes;
  int? get durationOverrideMinutes => _$this._durationOverrideMinutes;
  set durationOverrideMinutes(int? durationOverrideMinutes) =>
      _$this._durationOverrideMinutes = durationOverrideMinutes;

  num? _effectivePrice;
  num? get effectivePrice => _$this._effectivePrice;
  set effectivePrice(num? effectivePrice) =>
      _$this._effectivePrice = effectivePrice;

  int? _effectiveDurationMinutes;
  int? get effectiveDurationMinutes => _$this._effectiveDurationMinutes;
  set effectiveDurationMinutes(int? effectiveDurationMinutes) =>
      _$this._effectiveDurationMinutes = effectiveDurationMinutes;

  bool? _isActive;
  bool? get isActive => _$this._isActive;
  set isActive(bool? isActive) => _$this._isActive = isActive;

  MasterServiceResponsePriceTypeEnum? _priceType;
  MasterServiceResponsePriceTypeEnum? get priceType => _$this._priceType;
  set priceType(MasterServiceResponsePriceTypeEnum? priceType) =>
      _$this._priceType = priceType;

  num? _priceMin;
  num? get priceMin => _$this._priceMin;
  set priceMin(num? priceMin) => _$this._priceMin = priceMin;

  num? _priceMax;
  num? get priceMax => _$this._priceMax;
  set priceMax(num? priceMax) => _$this._priceMax = priceMax;

  String? _priceDisplay;
  String? get priceDisplay => _$this._priceDisplay;
  set priceDisplay(String? priceDisplay) => _$this._priceDisplay = priceDisplay;

  String? _serviceTypeId;
  String? get serviceTypeId => _$this._serviceTypeId;
  set serviceTypeId(String? serviceTypeId) =>
      _$this._serviceTypeId = serviceTypeId;

  String? _serviceTypeNameUk;
  String? get serviceTypeNameUk => _$this._serviceTypeNameUk;
  set serviceTypeNameUk(String? serviceTypeNameUk) =>
      _$this._serviceTypeNameUk = serviceTypeNameUk;

  bool? _isDraft;
  bool? get isDraft => _$this._isDraft;
  set isDraft(bool? isDraft) => _$this._isDraft = isDraft;

  MasterServiceResponseBuilder() {
    MasterServiceResponse._defaults(this);
  }

  MasterServiceResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _masterId = $v.masterId;
      _serviceDefinition = $v.serviceDefinition?.toBuilder();
      _priceOverride = $v.priceOverride;
      _durationOverrideMinutes = $v.durationOverrideMinutes;
      _effectivePrice = $v.effectivePrice;
      _effectiveDurationMinutes = $v.effectiveDurationMinutes;
      _isActive = $v.isActive;
      _priceType = $v.priceType;
      _priceMin = $v.priceMin;
      _priceMax = $v.priceMax;
      _priceDisplay = $v.priceDisplay;
      _serviceTypeId = $v.serviceTypeId;
      _serviceTypeNameUk = $v.serviceTypeNameUk;
      _isDraft = $v.isDraft;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MasterServiceResponse other) {
    _$v = other as _$MasterServiceResponse;
  }

  @override
  void update(void Function(MasterServiceResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterServiceResponse build() => _build();

  _$MasterServiceResponse _build() {
    _$MasterServiceResponse _$result;
    try {
      _$result = _$v ??
          _$MasterServiceResponse._(
            id: id,
            masterId: masterId,
            serviceDefinition: _serviceDefinition?.build(),
            priceOverride: priceOverride,
            durationOverrideMinutes: durationOverrideMinutes,
            effectivePrice: effectivePrice,
            effectiveDurationMinutes: effectiveDurationMinutes,
            isActive: isActive,
            priceType: priceType,
            priceMin: priceMin,
            priceMax: priceMax,
            priceDisplay: priceDisplay,
            serviceTypeId: serviceTypeId,
            serviceTypeNameUk: serviceTypeNameUk,
            isDraft: isDraft,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'serviceDefinition';
        _serviceDefinition?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MasterServiceResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
