// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_master_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FavoriteMasterResponse extends FavoriteMasterResponse {
  @override
  final String? masterId;
  @override
  final String? firstName;
  @override
  final String? lastName;
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

  factory _$FavoriteMasterResponse(
          [void Function(FavoriteMasterResponseBuilder)? updates]) =>
      (FavoriteMasterResponseBuilder()..update(updates))._build();

  _$FavoriteMasterResponse._(
      {this.masterId,
      this.firstName,
      this.lastName,
      this.avatarUrl,
      this.cityLabel,
      this.districtLabel,
      this.avgRating,
      this.street,
      this.buildingNo,
      this.locationNote})
      : super._();
  @override
  FavoriteMasterResponse rebuild(
          void Function(FavoriteMasterResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FavoriteMasterResponseBuilder toBuilder() =>
      FavoriteMasterResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FavoriteMasterResponse &&
        masterId == other.masterId &&
        firstName == other.firstName &&
        lastName == other.lastName &&
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
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
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
    return (newBuiltValueToStringHelper(r'FavoriteMasterResponse')
          ..add('masterId', masterId)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
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

class FavoriteMasterResponseBuilder
    implements Builder<FavoriteMasterResponse, FavoriteMasterResponseBuilder> {
  _$FavoriteMasterResponse? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

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

  FavoriteMasterResponseBuilder() {
    FavoriteMasterResponse._defaults(this);
  }

  FavoriteMasterResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
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
  void replace(FavoriteMasterResponse other) {
    _$v = other as _$FavoriteMasterResponse;
  }

  @override
  void update(void Function(FavoriteMasterResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FavoriteMasterResponse build() => _build();

  _$FavoriteMasterResponse _build() {
    final _$result = _$v ??
        _$FavoriteMasterResponse._(
          masterId: masterId,
          firstName: firstName,
          lastName: lastName,
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
