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
  final String? instagramUrl;
  @override
  final String? avatarUrl;

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
      this.instagramUrl,
      this.avatarUrl})
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
        instagramUrl == other.instagramUrl &&
        avatarUrl == other.avatarUrl;
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
    _$hash = $jc(_$hash, instagramUrl.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
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
          ..add('instagramUrl', instagramUrl)
          ..add('avatarUrl', avatarUrl))
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

  String? _instagramUrl;
  String? get instagramUrl => _$this._instagramUrl;
  set instagramUrl(String? instagramUrl) => _$this._instagramUrl = instagramUrl;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

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
      _instagramUrl = $v.instagramUrl;
      _avatarUrl = $v.avatarUrl;
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
          instagramUrl: instagramUrl,
          avatarUrl: avatarUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
