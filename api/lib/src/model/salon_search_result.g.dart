// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_search_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonSearchResult extends SalonSearchResult {
  @override
  final String? salonId;
  @override
  final String? name;
  @override
  final String? cityLabel;
  @override
  final String? districtLabel;
  @override
  final String? avatarUrl;
  @override
  final num? priceMin;
  @override
  final num? priceMax;
  @override
  final BuiltList<String>? serviceNames;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;
  @override
  final BuiltList<String>? matchedServiceNames;

  factory _$SalonSearchResult(
          [void Function(SalonSearchResultBuilder)? updates]) =>
      (SalonSearchResultBuilder()..update(updates))._build();

  _$SalonSearchResult._(
      {this.salonId,
      this.name,
      this.cityLabel,
      this.districtLabel,
      this.avatarUrl,
      this.priceMin,
      this.priceMax,
      this.serviceNames,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.matchedServiceNames})
      : super._();
  @override
  SalonSearchResult rebuild(void Function(SalonSearchResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonSearchResultBuilder toBuilder() =>
      SalonSearchResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonSearchResult &&
        salonId == other.salonId &&
        name == other.name &&
        cityLabel == other.cityLabel &&
        districtLabel == other.districtLabel &&
        avatarUrl == other.avatarUrl &&
        priceMin == other.priceMin &&
        priceMax == other.priceMax &&
        serviceNames == other.serviceNames &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        matchedServiceNames == other.matchedServiceNames;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, cityLabel.hashCode);
    _$hash = $jc(_$hash, districtLabel.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, priceMin.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jc(_$hash, serviceNames.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, matchedServiceNames.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonSearchResult')
          ..add('salonId', salonId)
          ..add('name', name)
          ..add('cityLabel', cityLabel)
          ..add('districtLabel', districtLabel)
          ..add('avatarUrl', avatarUrl)
          ..add('priceMin', priceMin)
          ..add('priceMax', priceMax)
          ..add('serviceNames', serviceNames)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('matchedServiceNames', matchedServiceNames))
        .toString();
  }
}

class SalonSearchResultBuilder
    implements Builder<SalonSearchResult, SalonSearchResultBuilder> {
  _$SalonSearchResult? _$v;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _cityLabel;
  String? get cityLabel => _$this._cityLabel;
  set cityLabel(String? cityLabel) => _$this._cityLabel = cityLabel;

  String? _districtLabel;
  String? get districtLabel => _$this._districtLabel;
  set districtLabel(String? districtLabel) =>
      _$this._districtLabel = districtLabel;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  num? _priceMin;
  num? get priceMin => _$this._priceMin;
  set priceMin(num? priceMin) => _$this._priceMin = priceMin;

  num? _priceMax;
  num? get priceMax => _$this._priceMax;
  set priceMax(num? priceMax) => _$this._priceMax = priceMax;

  ListBuilder<String>? _serviceNames;
  ListBuilder<String> get serviceNames =>
      _$this._serviceNames ??= ListBuilder<String>();
  set serviceNames(ListBuilder<String>? serviceNames) =>
      _$this._serviceNames = serviceNames;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  ListBuilder<String>? _matchedServiceNames;
  ListBuilder<String> get matchedServiceNames =>
      _$this._matchedServiceNames ??= ListBuilder<String>();
  set matchedServiceNames(ListBuilder<String>? matchedServiceNames) =>
      _$this._matchedServiceNames = matchedServiceNames;

  SalonSearchResultBuilder() {
    SalonSearchResult._defaults(this);
  }

  SalonSearchResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _salonId = $v.salonId;
      _name = $v.name;
      _cityLabel = $v.cityLabel;
      _districtLabel = $v.districtLabel;
      _avatarUrl = $v.avatarUrl;
      _priceMin = $v.priceMin;
      _priceMax = $v.priceMax;
      _serviceNames = $v.serviceNames?.toBuilder();
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _matchedServiceNames = $v.matchedServiceNames?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonSearchResult other) {
    _$v = other as _$SalonSearchResult;
  }

  @override
  void update(void Function(SalonSearchResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonSearchResult build() => _build();

  _$SalonSearchResult _build() {
    _$SalonSearchResult _$result;
    try {
      _$result = _$v ??
          _$SalonSearchResult._(
            salonId: salonId,
            name: name,
            cityLabel: cityLabel,
            districtLabel: districtLabel,
            avatarUrl: avatarUrl,
            priceMin: priceMin,
            priceMax: priceMax,
            serviceNames: _serviceNames?.build(),
            street: street,
            buildingNo: buildingNo,
            locationNote: locationNote,
            matchedServiceNames: _matchedServiceNames?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'serviceNames';
        _serviceNames?.build();

        _$failedField = 'matchedServiceNames';
        _matchedServiceNames?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonSearchResult', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
