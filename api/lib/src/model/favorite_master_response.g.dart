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
  final String? salonId;
  @override
  final String? salonName;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;
  @override
  final String? categoryCode;
  @override
  final String? categoryLabel;

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
      this.salonId,
      this.salonName,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.categoryCode,
      this.categoryLabel})
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
        salonId == other.salonId &&
        salonName == other.salonName &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        categoryCode == other.categoryCode &&
        categoryLabel == other.categoryLabel;
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
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, salonName.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, categoryCode.hashCode);
    _$hash = $jc(_$hash, categoryLabel.hashCode);
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
          ..add('salonId', salonId)
          ..add('salonName', salonName)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('categoryCode', categoryCode)
          ..add('categoryLabel', categoryLabel))
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

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  String? _salonName;
  String? get salonName => _$this._salonName;
  set salonName(String? salonName) => _$this._salonName = salonName;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  String? _categoryCode;
  String? get categoryCode => _$this._categoryCode;
  set categoryCode(String? categoryCode) => _$this._categoryCode = categoryCode;

  String? _categoryLabel;
  String? get categoryLabel => _$this._categoryLabel;
  set categoryLabel(String? categoryLabel) =>
      _$this._categoryLabel = categoryLabel;

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
      _salonId = $v.salonId;
      _salonName = $v.salonName;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _categoryCode = $v.categoryCode;
      _categoryLabel = $v.categoryLabel;
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
          salonId: salonId,
          salonName: salonName,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
          categoryCode: categoryCode,
          categoryLabel: categoryLabel,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
