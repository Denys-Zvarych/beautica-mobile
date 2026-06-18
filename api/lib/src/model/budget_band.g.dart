// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'budget_band.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BudgetBand extends BudgetBand {
  @override
  final num? avg;
  @override
  final num? min;
  @override
  final num? max;
  @override
  final String? currency;

  factory _$BudgetBand([void Function(BudgetBandBuilder)? updates]) =>
      (BudgetBandBuilder()..update(updates))._build();

  _$BudgetBand._({this.avg, this.min, this.max, this.currency}) : super._();
  @override
  BudgetBand rebuild(void Function(BudgetBandBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BudgetBandBuilder toBuilder() => BudgetBandBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BudgetBand &&
        avg == other.avg &&
        min == other.min &&
        max == other.max &&
        currency == other.currency;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, avg.hashCode);
    _$hash = $jc(_$hash, min.hashCode);
    _$hash = $jc(_$hash, max.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BudgetBand')
          ..add('avg', avg)
          ..add('min', min)
          ..add('max', max)
          ..add('currency', currency))
        .toString();
  }
}

class BudgetBandBuilder implements Builder<BudgetBand, BudgetBandBuilder> {
  _$BudgetBand? _$v;

  num? _avg;
  num? get avg => _$this._avg;
  set avg(num? avg) => _$this._avg = avg;

  num? _min;
  num? get min => _$this._min;
  set min(num? min) => _$this._min = min;

  num? _max;
  num? get max => _$this._max;
  set max(num? max) => _$this._max = max;

  String? _currency;
  String? get currency => _$this._currency;
  set currency(String? currency) => _$this._currency = currency;

  BudgetBandBuilder() {
    BudgetBand._defaults(this);
  }

  BudgetBandBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _avg = $v.avg;
      _min = $v.min;
      _max = $v.max;
      _currency = $v.currency;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BudgetBand other) {
    _$v = other as _$BudgetBand;
  }

  @override
  void update(void Function(BudgetBandBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BudgetBand build() => _build();

  _$BudgetBand _build() {
    final _$result = _$v ??
        _$BudgetBand._(
          avg: avg,
          min: min,
          max: max,
          currency: currency,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
