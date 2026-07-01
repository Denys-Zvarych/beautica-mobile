// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_profile_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateProfileRequest extends UpdateProfileRequest {
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? phoneNumber;
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
  final String? instagram;

  factory _$UpdateProfileRequest(
          [void Function(UpdateProfileRequestBuilder)? updates]) =>
      (UpdateProfileRequestBuilder()..update(updates))._build();

  _$UpdateProfileRequest._(
      {this.firstName,
      this.lastName,
      this.phoneNumber,
      this.cityId,
      this.districtId,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.instagram})
      : super._();
  @override
  UpdateProfileRequest rebuild(
          void Function(UpdateProfileRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateProfileRequestBuilder toBuilder() =>
      UpdateProfileRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateProfileRequest &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        phoneNumber == other.phoneNumber &&
        cityId == other.cityId &&
        districtId == other.districtId &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        instagram == other.instagram;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, instagram.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateProfileRequest')
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber)
          ..add('cityId', cityId)
          ..add('districtId', districtId)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('instagram', instagram))
        .toString();
  }
}

class UpdateProfileRequestBuilder
    implements Builder<UpdateProfileRequest, UpdateProfileRequestBuilder> {
  _$UpdateProfileRequest? _$v;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _phoneNumber;
  String? get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String? phoneNumber) => _$this._phoneNumber = phoneNumber;

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

  String? _instagram;
  String? get instagram => _$this._instagram;
  set instagram(String? instagram) => _$this._instagram = instagram;

  UpdateProfileRequestBuilder() {
    UpdateProfileRequest._defaults(this);
  }

  UpdateProfileRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _phoneNumber = $v.phoneNumber;
      _cityId = $v.cityId;
      _districtId = $v.districtId;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _instagram = $v.instagram;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateProfileRequest other) {
    _$v = other as _$UpdateProfileRequest;
  }

  @override
  void update(void Function(UpdateProfileRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateProfileRequest build() => _build();

  _$UpdateProfileRequest _build() {
    final _$result = _$v ??
        _$UpdateProfileRequest._(
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phoneNumber,
          cityId: cityId,
          districtId: districtId,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
          instagram: instagram,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
