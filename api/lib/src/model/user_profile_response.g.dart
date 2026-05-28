// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UserProfileResponse extends UserProfileResponse {
  @override
  final String? id;
  @override
  final String? email;
  @override
  final String? role;
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
  final bool? isActive;
  @override
  final bool? emailVerified;
  @override
  final String? salonId;

  factory _$UserProfileResponse(
          [void Function(UserProfileResponseBuilder)? updates]) =>
      (UserProfileResponseBuilder()..update(updates))._build();

  _$UserProfileResponse._(
      {this.id,
      this.email,
      this.role,
      this.firstName,
      this.lastName,
      this.phoneNumber,
      this.cityId,
      this.districtId,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.isActive,
      this.emailVerified,
      this.salonId})
      : super._();
  @override
  UserProfileResponse rebuild(
          void Function(UserProfileResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserProfileResponseBuilder toBuilder() =>
      UserProfileResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserProfileResponse &&
        id == other.id &&
        email == other.email &&
        role == other.role &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        phoneNumber == other.phoneNumber &&
        cityId == other.cityId &&
        districtId == other.districtId &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        isActive == other.isActive &&
        emailVerified == other.emailVerified &&
        salonId == other.salonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, isActive.hashCode);
    _$hash = $jc(_$hash, emailVerified.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UserProfileResponse')
          ..add('id', id)
          ..add('email', email)
          ..add('role', role)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber)
          ..add('cityId', cityId)
          ..add('districtId', districtId)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('isActive', isActive)
          ..add('emailVerified', emailVerified)
          ..add('salonId', salonId))
        .toString();
  }
}

class UserProfileResponseBuilder
    implements Builder<UserProfileResponse, UserProfileResponseBuilder> {
  _$UserProfileResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

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

  bool? _isActive;
  bool? get isActive => _$this._isActive;
  set isActive(bool? isActive) => _$this._isActive = isActive;

  bool? _emailVerified;
  bool? get emailVerified => _$this._emailVerified;
  set emailVerified(bool? emailVerified) =>
      _$this._emailVerified = emailVerified;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  UserProfileResponseBuilder() {
    UserProfileResponse._defaults(this);
  }

  UserProfileResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _email = $v.email;
      _role = $v.role;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _phoneNumber = $v.phoneNumber;
      _cityId = $v.cityId;
      _districtId = $v.districtId;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _isActive = $v.isActive;
      _emailVerified = $v.emailVerified;
      _salonId = $v.salonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserProfileResponse other) {
    _$v = other as _$UserProfileResponse;
  }

  @override
  void update(void Function(UserProfileResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UserProfileResponse build() => _build();

  _$UserProfileResponse _build() {
    final _$result = _$v ??
        _$UserProfileResponse._(
          id: id,
          email: email,
          role: role,
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phoneNumber,
          cityId: cityId,
          districtId: districtId,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
          isActive: isActive,
          emailVerified: emailVerified,
          salonId: salonId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
