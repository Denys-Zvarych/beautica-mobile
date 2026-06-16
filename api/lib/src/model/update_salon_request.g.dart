// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_salon_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateSalonRequest extends UpdateSalonRequest {
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
  final String? cityId;
  @override
  final String? districtId;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;
  @override
  final String? phone;
  @override
  final String? instagramUrl;

  factory _$UpdateSalonRequest(
          [void Function(UpdateSalonRequestBuilder)? updates]) =>
      (UpdateSalonRequestBuilder()..update(updates))._build();

  _$UpdateSalonRequest._(
      {this.name,
      this.description,
      this.city,
      this.region,
      this.address,
      this.cityId,
      this.districtId,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.phone,
      this.instagramUrl})
      : super._();
  @override
  UpdateSalonRequest rebuild(
          void Function(UpdateSalonRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateSalonRequestBuilder toBuilder() =>
      UpdateSalonRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateSalonRequest &&
        name == other.name &&
        description == other.description &&
        city == other.city &&
        region == other.region &&
        address == other.address &&
        cityId == other.cityId &&
        districtId == other.districtId &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        phone == other.phone &&
        instagramUrl == other.instagramUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, city.hashCode);
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, address.hashCode);
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, instagramUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateSalonRequest')
          ..add('name', name)
          ..add('description', description)
          ..add('city', city)
          ..add('region', region)
          ..add('address', address)
          ..add('cityId', cityId)
          ..add('districtId', districtId)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('phone', phone)
          ..add('instagramUrl', instagramUrl))
        .toString();
  }
}

class UpdateSalonRequestBuilder
    implements Builder<UpdateSalonRequest, UpdateSalonRequestBuilder> {
  _$UpdateSalonRequest? _$v;

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

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  String? _instagramUrl;
  String? get instagramUrl => _$this._instagramUrl;
  set instagramUrl(String? instagramUrl) => _$this._instagramUrl = instagramUrl;

  UpdateSalonRequestBuilder() {
    UpdateSalonRequest._defaults(this);
  }

  UpdateSalonRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _description = $v.description;
      _city = $v.city;
      _region = $v.region;
      _address = $v.address;
      _cityId = $v.cityId;
      _districtId = $v.districtId;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _phone = $v.phone;
      _instagramUrl = $v.instagramUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateSalonRequest other) {
    _$v = other as _$UpdateSalonRequest;
  }

  @override
  void update(void Function(UpdateSalonRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateSalonRequest build() => _build();

  _$UpdateSalonRequest _build() {
    final _$result = _$v ??
        _$UpdateSalonRequest._(
          name: name,
          description: description,
          city: city,
          region: region,
          address: address,
          cityId: cityId,
          districtId: districtId,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
          phone: phone,
          instagramUrl: instagramUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
