// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'revenue_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RevenueResponse extends RevenueResponse {
  @override
  final int? totalCompletedBookings;
  @override
  final num? estimatedRevenue;
  @override
  final BuiltList<RevenueByMasterDto>? byMaster;
  @override
  final BuiltList<RevenueByServiceDto>? byService;
  @override
  final BuiltList<RevenueByDateDto>? byDate;

  factory _$RevenueResponse([void Function(RevenueResponseBuilder)? updates]) =>
      (RevenueResponseBuilder()..update(updates))._build();

  _$RevenueResponse._(
      {this.totalCompletedBookings,
      this.estimatedRevenue,
      this.byMaster,
      this.byService,
      this.byDate})
      : super._();
  @override
  RevenueResponse rebuild(void Function(RevenueResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RevenueResponseBuilder toBuilder() => RevenueResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RevenueResponse &&
        totalCompletedBookings == other.totalCompletedBookings &&
        estimatedRevenue == other.estimatedRevenue &&
        byMaster == other.byMaster &&
        byService == other.byService &&
        byDate == other.byDate;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, totalCompletedBookings.hashCode);
    _$hash = $jc(_$hash, estimatedRevenue.hashCode);
    _$hash = $jc(_$hash, byMaster.hashCode);
    _$hash = $jc(_$hash, byService.hashCode);
    _$hash = $jc(_$hash, byDate.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RevenueResponse')
          ..add('totalCompletedBookings', totalCompletedBookings)
          ..add('estimatedRevenue', estimatedRevenue)
          ..add('byMaster', byMaster)
          ..add('byService', byService)
          ..add('byDate', byDate))
        .toString();
  }
}

class RevenueResponseBuilder
    implements Builder<RevenueResponse, RevenueResponseBuilder> {
  _$RevenueResponse? _$v;

  int? _totalCompletedBookings;
  int? get totalCompletedBookings => _$this._totalCompletedBookings;
  set totalCompletedBookings(int? totalCompletedBookings) =>
      _$this._totalCompletedBookings = totalCompletedBookings;

  num? _estimatedRevenue;
  num? get estimatedRevenue => _$this._estimatedRevenue;
  set estimatedRevenue(num? estimatedRevenue) =>
      _$this._estimatedRevenue = estimatedRevenue;

  ListBuilder<RevenueByMasterDto>? _byMaster;
  ListBuilder<RevenueByMasterDto> get byMaster =>
      _$this._byMaster ??= ListBuilder<RevenueByMasterDto>();
  set byMaster(ListBuilder<RevenueByMasterDto>? byMaster) =>
      _$this._byMaster = byMaster;

  ListBuilder<RevenueByServiceDto>? _byService;
  ListBuilder<RevenueByServiceDto> get byService =>
      _$this._byService ??= ListBuilder<RevenueByServiceDto>();
  set byService(ListBuilder<RevenueByServiceDto>? byService) =>
      _$this._byService = byService;

  ListBuilder<RevenueByDateDto>? _byDate;
  ListBuilder<RevenueByDateDto> get byDate =>
      _$this._byDate ??= ListBuilder<RevenueByDateDto>();
  set byDate(ListBuilder<RevenueByDateDto>? byDate) => _$this._byDate = byDate;

  RevenueResponseBuilder() {
    RevenueResponse._defaults(this);
  }

  RevenueResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _totalCompletedBookings = $v.totalCompletedBookings;
      _estimatedRevenue = $v.estimatedRevenue;
      _byMaster = $v.byMaster?.toBuilder();
      _byService = $v.byService?.toBuilder();
      _byDate = $v.byDate?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RevenueResponse other) {
    _$v = other as _$RevenueResponse;
  }

  @override
  void update(void Function(RevenueResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RevenueResponse build() => _build();

  _$RevenueResponse _build() {
    _$RevenueResponse _$result;
    try {
      _$result = _$v ??
          _$RevenueResponse._(
            totalCompletedBookings: totalCompletedBookings,
            estimatedRevenue: estimatedRevenue,
            byMaster: _byMaster?.build(),
            byService: _byService?.build(),
            byDate: _byDate?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'byMaster';
        _byMaster?.build();
        _$failedField = 'byService';
        _byService?.build();
        _$failedField = 'byDate';
        _byDate?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'RevenueResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
