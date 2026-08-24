// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_salon_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FavoriteSalonResponse extends FavoriteSalonResponse {
  @override
  final String? salonId;
  @override
  final String? name;
  @override
  final String? avatarUrl;
  @override
  final String? cityLabel;
  @override
  final String? districtLabel;
  @override
  final double? avgRating;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;

  factory _$FavoriteSalonResponse(
          [void Function(FavoriteSalonResponseBuilder)? updates]) =>
      (FavoriteSalonResponseBuilder()..update(updates))._build();

  _$FavoriteSalonResponse._(
      {this.salonId,
      this.name,
      this.avatarUrl,
      this.cityLabel,
      this.districtLabel,
      this.avgRating,
      this.street,
      this.buildingNo,
      this.locationNote})
      : super._();
  @override
  FavoriteSalonResponse rebuild(
          void Function(FavoriteSalonResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FavoriteSalonResponseBuilder toBuilder() =>
      FavoriteSalonResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FavoriteSalonResponse &&
        salonId == other.salonId &&
        name == other.name &&
        avatarUrl == other.avatarUrl &&
        cityLabel == other.cityLabel &&
        districtLabel == other.districtLabel &&
        avgRating == other.avgRating &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, cityLabel.hashCode);
    _$hash = $jc(_$hash, districtLabel.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FavoriteSalonResponse')
          ..add('salonId', salonId)
          ..add('name', name)
          ..add('avatarUrl', avatarUrl)
          ..add('cityLabel', cityLabel)
          ..add('districtLabel', districtLabel)
          ..add('avgRating', avgRating)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote))
        .toString();
  }
}

class FavoriteSalonResponseBuilder
    implements Builder<FavoriteSalonResponse, FavoriteSalonResponseBuilder> {
  _$FavoriteSalonResponse? _$v;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  String? _cityLabel;
  String? get cityLabel => _$this._cityLabel;
  set cityLabel(String? cityLabel) => _$this._cityLabel = cityLabel;

  String? _districtLabel;
  String? get districtLabel => _$this._districtLabel;
  set districtLabel(String? districtLabel) =>
      _$this._districtLabel = districtLabel;

  double? _avgRating;
  double? get avgRating => _$this._avgRating;
  set avgRating(double? avgRating) => _$this._avgRating = avgRating;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  FavoriteSalonResponseBuilder() {
    FavoriteSalonResponse._defaults(this);
  }

  FavoriteSalonResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _salonId = $v.salonId;
      _name = $v.name;
      _avatarUrl = $v.avatarUrl;
      _cityLabel = $v.cityLabel;
      _districtLabel = $v.districtLabel;
      _avgRating = $v.avgRating;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FavoriteSalonResponse other) {
    _$v = other as _$FavoriteSalonResponse;
  }

  @override
  void update(void Function(FavoriteSalonResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FavoriteSalonResponse build() => _build();

  _$FavoriteSalonResponse _build() {
    final _$result = _$v ??
        _$FavoriteSalonResponse._(
          salonId: salonId,
          name: name,
          avatarUrl: avatarUrl,
          cityLabel: cityLabel,
          districtLabel: districtLabel,
          avgRating: avgRating,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
