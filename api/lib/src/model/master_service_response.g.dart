// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_service_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

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
      this.isActive})
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
        isActive == other.isActive;
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
          ..add('isActive', isActive))
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
