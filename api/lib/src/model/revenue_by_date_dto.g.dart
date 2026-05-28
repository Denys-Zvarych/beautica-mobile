// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'revenue_by_date_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RevenueByDateDto extends RevenueByDateDto {
  @override
  final Date? date;
  @override
  final int? bookingCount;
  @override
  final num? revenue;

  factory _$RevenueByDateDto(
          [void Function(RevenueByDateDtoBuilder)? updates]) =>
      (RevenueByDateDtoBuilder()..update(updates))._build();

  _$RevenueByDateDto._({this.date, this.bookingCount, this.revenue})
      : super._();
  @override
  RevenueByDateDto rebuild(void Function(RevenueByDateDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RevenueByDateDtoBuilder toBuilder() =>
      RevenueByDateDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RevenueByDateDto &&
        date == other.date &&
        bookingCount == other.bookingCount &&
        revenue == other.revenue;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, bookingCount.hashCode);
    _$hash = $jc(_$hash, revenue.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RevenueByDateDto')
          ..add('date', date)
          ..add('bookingCount', bookingCount)
          ..add('revenue', revenue))
        .toString();
  }
}

class RevenueByDateDtoBuilder
    implements Builder<RevenueByDateDto, RevenueByDateDtoBuilder> {
  _$RevenueByDateDto? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  int? _bookingCount;
  int? get bookingCount => _$this._bookingCount;
  set bookingCount(int? bookingCount) => _$this._bookingCount = bookingCount;

  num? _revenue;
  num? get revenue => _$this._revenue;
  set revenue(num? revenue) => _$this._revenue = revenue;

  RevenueByDateDtoBuilder() {
    RevenueByDateDto._defaults(this);
  }

  RevenueByDateDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _bookingCount = $v.bookingCount;
      _revenue = $v.revenue;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RevenueByDateDto other) {
    _$v = other as _$RevenueByDateDto;
  }

  @override
  void update(void Function(RevenueByDateDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RevenueByDateDto build() => _build();

  _$RevenueByDateDto _build() {
    final _$result = _$v ??
        _$RevenueByDateDto._(
          date: date,
          bookingCount: bookingCount,
          revenue: revenue,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
