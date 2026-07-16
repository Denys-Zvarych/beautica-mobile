// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_salon_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateSalonRequest extends CreateSalonRequest {
  @override
  final String name;
  @override
  final String? description;
  @override
  final String? city;
  @override
  final String? region;
  @override
  final String? address;
  @override
  final String? phone;
  @override
  final String? instagramUrl;
  @override
  final String? cityId;
  @override
  final String? districtId;
  @override
  final String street;
  @override
  final String buildingNo;
  @override
  final String? locationNote;

  factory _$CreateSalonRequest(
          [void Function(CreateSalonRequestBuilder)? updates]) =>
      (CreateSalonRequestBuilder()..update(updates))._build();

  _$CreateSalonRequest._(
      {required this.name,
      this.description,
      this.city,
      this.region,
      this.address,
      this.phone,
      this.instagramUrl,
      this.cityId,
      this.districtId,
      required this.street,
      required this.buildingNo,
      this.locationNote})
      : super._();
  @override
  CreateSalonRequest rebuild(
          void Function(CreateSalonRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateSalonRequestBuilder toBuilder() =>
      CreateSalonRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateSalonRequest &&
        name == other.name &&
        description == other.description &&
        city == other.city &&
        region == other.region &&
        address == other.address &&
        phone == other.phone &&
        instagramUrl == other.instagramUrl &&
        cityId == other.cityId &&
        districtId == other.districtId &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, city.hashCode);
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, address.hashCode);
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, instagramUrl.hashCode);
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateSalonRequest')
          ..add('name', name)
          ..add('description', description)
          ..add('city', city)
          ..add('region', region)
          ..add('address', address)
          ..add('phone', phone)
          ..add('instagramUrl', instagramUrl)
          ..add('cityId', cityId)
          ..add('districtId', districtId)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote))
        .toString();
  }
}

class CreateSalonRequestBuilder
    implements Builder<CreateSalonRequest, CreateSalonRequestBuilder> {
  _$CreateSalonRequest? _$v;

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

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  String? _instagramUrl;
  String? get instagramUrl => _$this._instagramUrl;
  set instagramUrl(String? instagramUrl) => _$this._instagramUrl = instagramUrl;

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

  CreateSalonRequestBuilder() {
    CreateSalonRequest._defaults(this);
  }

  CreateSalonRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _description = $v.description;
      _city = $v.city;
      _region = $v.region;
      _address = $v.address;
      _phone = $v.phone;
      _instagramUrl = $v.instagramUrl;
      _cityId = $v.cityId;
      _districtId = $v.districtId;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateSalonRequest other) {
    _$v = other as _$CreateSalonRequest;
  }

  @override
  void update(void Function(CreateSalonRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateSalonRequest build() => _build();

  _$CreateSalonRequest _build() {
    final _$result = _$v ??
        _$CreateSalonRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CreateSalonRequest', 'name'),
          description: description,
          city: city,
          region: region,
          address: address,
          phone: phone,
          instagramUrl: instagramUrl,
          cityId: cityId,
          districtId: districtId,
          street: BuiltValueNullFieldError.checkNotNull(
              street, r'CreateSalonRequest', 'street'),
          buildingNo: BuiltValueNullFieldError.checkNotNull(
              buildingNo, r'CreateSalonRequest', 'buildingNo'),
          locationNote: locationNote,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
