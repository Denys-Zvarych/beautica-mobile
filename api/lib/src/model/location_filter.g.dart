// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_filter.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LocationFilter extends LocationFilter {
  @override
  final String? cityId;
  @override
  final String? districtId;

  factory _$LocationFilter([void Function(LocationFilterBuilder)? updates]) =>
      (LocationFilterBuilder()..update(updates))._build();

  _$LocationFilter._({this.cityId, this.districtId}) : super._();
  @override
  LocationFilter rebuild(void Function(LocationFilterBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LocationFilterBuilder toBuilder() => LocationFilterBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LocationFilter &&
        cityId == other.cityId &&
        districtId == other.districtId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LocationFilter')
          ..add('cityId', cityId)
          ..add('districtId', districtId))
        .toString();
  }
}

class LocationFilterBuilder
    implements Builder<LocationFilter, LocationFilterBuilder> {
  _$LocationFilter? _$v;

  String? _cityId;
  String? get cityId => _$this._cityId;
  set cityId(String? cityId) => _$this._cityId = cityId;

  String? _districtId;
  String? get districtId => _$this._districtId;
  set districtId(String? districtId) => _$this._districtId = districtId;

  LocationFilterBuilder() {
    LocationFilter._defaults(this);
  }

  LocationFilterBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cityId = $v.cityId;
      _districtId = $v.districtId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LocationFilter other) {
    _$v = other as _$LocationFilter;
  }

  @override
  void update(void Function(LocationFilterBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LocationFilter build() => _build();

  _$LocationFilter _build() {
    final _$result = _$v ??
        _$LocationFilter._(
          cityId: cityId,
          districtId: districtId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
