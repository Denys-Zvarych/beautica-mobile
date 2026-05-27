// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assign_service_to_master_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AssignServiceToMasterRequest extends AssignServiceToMasterRequest {
  @override
  final String serviceDefId;
  @override
  final num? priceOverride;
  @override
  final int? durationOverrideMinutes;

  factory _$AssignServiceToMasterRequest(
          [void Function(AssignServiceToMasterRequestBuilder)? updates]) =>
      (AssignServiceToMasterRequestBuilder()..update(updates))._build();

  _$AssignServiceToMasterRequest._(
      {required this.serviceDefId,
      this.priceOverride,
      this.durationOverrideMinutes})
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
        priceOverride == other.priceOverride &&
        durationOverrideMinutes == other.durationOverrideMinutes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, serviceDefId.hashCode);
    _$hash = $jc(_$hash, priceOverride.hashCode);
    _$hash = $jc(_$hash, durationOverrideMinutes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AssignServiceToMasterRequest')
          ..add('serviceDefId', serviceDefId)
          ..add('priceOverride', priceOverride)
          ..add('durationOverrideMinutes', durationOverrideMinutes))
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

  num? _priceOverride;
  num? get priceOverride => _$this._priceOverride;
  set priceOverride(num? priceOverride) =>
      _$this._priceOverride = priceOverride;

  int? _durationOverrideMinutes;
  int? get durationOverrideMinutes => _$this._durationOverrideMinutes;
  set durationOverrideMinutes(int? durationOverrideMinutes) =>
      _$this._durationOverrideMinutes = durationOverrideMinutes;

  AssignServiceToMasterRequestBuilder() {
    AssignServiceToMasterRequest._defaults(this);
  }

  AssignServiceToMasterRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _serviceDefId = $v.serviceDefId;
      _priceOverride = $v.priceOverride;
      _durationOverrideMinutes = $v.durationOverrideMinutes;
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
          priceOverride: priceOverride,
          durationOverrideMinutes: durationOverrideMinutes,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
