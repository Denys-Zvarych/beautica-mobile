// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'revenue_by_master_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RevenueByMasterDto extends RevenueByMasterDto {
  @override
  final String? masterId;
  @override
  final String? masterName;
  @override
  final int? bookingCount;
  @override
  final num? revenue;

  factory _$RevenueByMasterDto(
          [void Function(RevenueByMasterDtoBuilder)? updates]) =>
      (RevenueByMasterDtoBuilder()..update(updates))._build();

  _$RevenueByMasterDto._(
      {this.masterId, this.masterName, this.bookingCount, this.revenue})
      : super._();
  @override
  RevenueByMasterDto rebuild(
          void Function(RevenueByMasterDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RevenueByMasterDtoBuilder toBuilder() =>
      RevenueByMasterDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RevenueByMasterDto &&
        masterId == other.masterId &&
        masterName == other.masterName &&
        bookingCount == other.bookingCount &&
        revenue == other.revenue;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterName.hashCode);
    _$hash = $jc(_$hash, bookingCount.hashCode);
    _$hash = $jc(_$hash, revenue.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RevenueByMasterDto')
          ..add('masterId', masterId)
          ..add('masterName', masterName)
          ..add('bookingCount', bookingCount)
          ..add('revenue', revenue))
        .toString();
  }
}

class RevenueByMasterDtoBuilder
    implements Builder<RevenueByMasterDto, RevenueByMasterDtoBuilder> {
  _$RevenueByMasterDto? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterName;
  String? get masterName => _$this._masterName;
  set masterName(String? masterName) => _$this._masterName = masterName;

  int? _bookingCount;
  int? get bookingCount => _$this._bookingCount;
  set bookingCount(int? bookingCount) => _$this._bookingCount = bookingCount;

  num? _revenue;
  num? get revenue => _$this._revenue;
  set revenue(num? revenue) => _$this._revenue = revenue;

  RevenueByMasterDtoBuilder() {
    RevenueByMasterDto._defaults(this);
  }

  RevenueByMasterDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _masterName = $v.masterName;
      _bookingCount = $v.bookingCount;
      _revenue = $v.revenue;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RevenueByMasterDto other) {
    _$v = other as _$RevenueByMasterDto;
  }

  @override
  void update(void Function(RevenueByMasterDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RevenueByMasterDto build() => _build();

  _$RevenueByMasterDto _build() {
    final _$result = _$v ??
        _$RevenueByMasterDto._(
          masterId: masterId,
          masterName: masterName,
          bookingCount: bookingCount,
          revenue: revenue,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
