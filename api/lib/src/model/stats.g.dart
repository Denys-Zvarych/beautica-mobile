// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Stats extends Stats {
  @override
  final int? totalVisits;
  @override
  final int? completedVisits;
  @override
  final int? upcomingVisits;

  factory _$Stats([void Function(StatsBuilder)? updates]) =>
      (StatsBuilder()..update(updates))._build();

  _$Stats._({this.totalVisits, this.completedVisits, this.upcomingVisits})
      : super._();
  @override
  Stats rebuild(void Function(StatsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StatsBuilder toBuilder() => StatsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Stats &&
        totalVisits == other.totalVisits &&
        completedVisits == other.completedVisits &&
        upcomingVisits == other.upcomingVisits;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, totalVisits.hashCode);
    _$hash = $jc(_$hash, completedVisits.hashCode);
    _$hash = $jc(_$hash, upcomingVisits.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Stats')
          ..add('totalVisits', totalVisits)
          ..add('completedVisits', completedVisits)
          ..add('upcomingVisits', upcomingVisits))
        .toString();
  }
}

class StatsBuilder implements Builder<Stats, StatsBuilder> {
  _$Stats? _$v;

  int? _totalVisits;
  int? get totalVisits => _$this._totalVisits;
  set totalVisits(int? totalVisits) => _$this._totalVisits = totalVisits;

  int? _completedVisits;
  int? get completedVisits => _$this._completedVisits;
  set completedVisits(int? completedVisits) =>
      _$this._completedVisits = completedVisits;

  int? _upcomingVisits;
  int? get upcomingVisits => _$this._upcomingVisits;
  set upcomingVisits(int? upcomingVisits) =>
      _$this._upcomingVisits = upcomingVisits;

  StatsBuilder() {
    Stats._defaults(this);
  }

  StatsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _totalVisits = $v.totalVisits;
      _completedVisits = $v.completedVisits;
      _upcomingVisits = $v.upcomingVisits;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Stats other) {
    _$v = other as _$Stats;
  }

  @override
  void update(void Function(StatsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Stats build() => _build();

  _$Stats _build() {
    final _$result = _$v ??
        _$Stats._(
          totalVisits: totalVisits,
          completedVisits: completedVisits,
          upcomingVisits: upcomingVisits,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
