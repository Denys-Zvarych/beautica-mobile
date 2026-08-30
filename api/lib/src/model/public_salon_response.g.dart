// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'public_salon_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PublicSalonResponse extends PublicSalonResponse {
  @override
  final String? id;
  @override
  final String? name;
  @override
  final String? description;
  @override
  final String? city;
  @override
  final String? region;
  @override
  final String? address;
  @override
  final String cityId;
  @override
  final String oblastId;
  @override
  final String? districtId;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;
  @override
  final String? instagramUrl;
  @override
  final String? avatarUrl;
  @override
  final String? coverImageUrl;
  @override
  final num? avgRating;
  @override
  final int? reviewCount;

  factory _$PublicSalonResponse(
          [void Function(PublicSalonResponseBuilder)? updates]) =>
      (PublicSalonResponseBuilder()..update(updates))._build();

  _$PublicSalonResponse._(
      {this.id,
      this.name,
      this.description,
      this.city,
      this.region,
      this.address,
      required this.cityId,
      required this.oblastId,
      this.districtId,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.instagramUrl,
      this.avatarUrl,
      this.coverImageUrl,
      this.avgRating,
      this.reviewCount})
      : super._();
  @override
  PublicSalonResponse rebuild(
          void Function(PublicSalonResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PublicSalonResponseBuilder toBuilder() =>
      PublicSalonResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PublicSalonResponse &&
        id == other.id &&
        name == other.name &&
        description == other.description &&
        city == other.city &&
        region == other.region &&
        address == other.address &&
        cityId == other.cityId &&
        oblastId == other.oblastId &&
        districtId == other.districtId &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        instagramUrl == other.instagramUrl &&
        avatarUrl == other.avatarUrl &&
        coverImageUrl == other.coverImageUrl &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, city.hashCode);
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, address.hashCode);
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, oblastId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, instagramUrl.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, coverImageUrl.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PublicSalonResponse')
          ..add('id', id)
          ..add('name', name)
          ..add('description', description)
          ..add('city', city)
          ..add('region', region)
          ..add('address', address)
          ..add('cityId', cityId)
          ..add('oblastId', oblastId)
          ..add('districtId', districtId)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('instagramUrl', instagramUrl)
          ..add('avatarUrl', avatarUrl)
          ..add('coverImageUrl', coverImageUrl)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount))
        .toString();
  }
}

class PublicSalonResponseBuilder
    implements Builder<PublicSalonResponse, PublicSalonResponseBuilder> {
  _$PublicSalonResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _city;
  String? get city => _$this._city;
  set city(String? city) => _$this._city = city;

  String? _region;
  String? get region => _$this._region;
  set region(String? region) => _$this._region = region;

  String? _address;
  String? get address => _$this._address;
  set address(String? address) => _$this._address = address;

  String? _cityId;
  String? get cityId => _$this._cityId;
  set cityId(String? cityId) => _$this._cityId = cityId;

  String? _oblastId;
  String? get oblastId => _$this._oblastId;
  set oblastId(String? oblastId) => _$this._oblastId = oblastId;

  String? _districtId;
  String? get districtId => _$this._districtId;
  set districtId(String? districtId) => _$this._districtId = districtId;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  String? _instagramUrl;
  String? get instagramUrl => _$this._instagramUrl;
  set instagramUrl(String? instagramUrl) => _$this._instagramUrl = instagramUrl;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  String? _coverImageUrl;
  String? get coverImageUrl => _$this._coverImageUrl;
  set coverImageUrl(String? coverImageUrl) =>
      _$this._coverImageUrl = coverImageUrl;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  PublicSalonResponseBuilder() {
    PublicSalonResponse._defaults(this);
  }

  PublicSalonResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _description = $v.description;
      _city = $v.city;
      _region = $v.region;
      _address = $v.address;
      _cityId = $v.cityId;
      _oblastId = $v.oblastId;
      _districtId = $v.districtId;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _instagramUrl = $v.instagramUrl;
      _avatarUrl = $v.avatarUrl;
      _coverImageUrl = $v.coverImageUrl;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PublicSalonResponse other) {
    _$v = other as _$PublicSalonResponse;
  }

  @override
  void update(void Function(PublicSalonResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PublicSalonResponse build() => _build();

  _$PublicSalonResponse _build() {
    final _$result = _$v ??
        _$PublicSalonResponse._(
          id: id,
          name: name,
          description: description,
          city: city,
          region: region,
          address: address,
          cityId: BuiltValueNullFieldError.checkNotNull(
              cityId, r'PublicSalonResponse', 'cityId'),
          oblastId: BuiltValueNullFieldError.checkNotNull(
              oblastId, r'PublicSalonResponse', 'oblastId'),
          districtId: districtId,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
          instagramUrl: instagramUrl,
          avatarUrl: avatarUrl,
          coverImageUrl: coverImageUrl,
          avgRating: avgRating,
          reviewCount: reviewCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
