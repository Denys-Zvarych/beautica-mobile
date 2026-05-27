// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'revenue_by_service_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RevenueByServiceDto extends RevenueByServiceDto {
  @override
  final String? serviceDefId;
  @override
  final String? serviceName;
  @override
  final int? bookingCount;
  @override
  final num? revenue;

  factory _$RevenueByServiceDto(
          [void Function(RevenueByServiceDtoBuilder)? updates]) =>
      (RevenueByServiceDtoBuilder()..update(updates))._build();

  _$RevenueByServiceDto._(
      {this.serviceDefId, this.serviceName, this.bookingCount, this.revenue})
      : super._();
  @override
  RevenueByServiceDto rebuild(
          void Function(RevenueByServiceDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RevenueByServiceDtoBuilder toBuilder() =>
      RevenueByServiceDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RevenueByServiceDto &&
        serviceDefId == other.serviceDefId &&
        serviceName == other.serviceName &&
        bookingCount == other.bookingCount &&
        revenue == other.revenue;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, serviceDefId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, bookingCount.hashCode);
    _$hash = $jc(_$hash, revenue.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RevenueByServiceDto')
          ..add('serviceDefId', serviceDefId)
          ..add('serviceName', serviceName)
          ..add('bookingCount', bookingCount)
          ..add('revenue', revenue))
        .toString();
  }
}

class RevenueByServiceDtoBuilder
    implements Builder<RevenueByServiceDto, RevenueByServiceDtoBuilder> {
  _$RevenueByServiceDto? _$v;

  String? _serviceDefId;
  String? get serviceDefId => _$this._serviceDefId;
  set serviceDefId(String? serviceDefId) => _$this._serviceDefId = serviceDefId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  int? _bookingCount;
  int? get bookingCount => _$this._bookingCount;
  set bookingCount(int? bookingCount) => _$this._bookingCount = bookingCount;

  num? _revenue;
  num? get revenue => _$this._revenue;
  set revenue(num? revenue) => _$this._revenue = revenue;

  RevenueByServiceDtoBuilder() {
    RevenueByServiceDto._defaults(this);
  }

  RevenueByServiceDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _serviceDefId = $v.serviceDefId;
      _serviceName = $v.serviceName;
      _bookingCount = $v.bookingCount;
      _revenue = $v.revenue;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RevenueByServiceDto other) {
    _$v = other as _$RevenueByServiceDto;
  }

  @override
  void update(void Function(RevenueByServiceDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RevenueByServiceDto build() => _build();

  _$RevenueByServiceDto _build() {
    final _$result = _$v ??
        _$RevenueByServiceDto._(
          serviceDefId: serviceDefId,
          serviceName: serviceName,
          bookingCount: bookingCount,
          revenue: revenue,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
