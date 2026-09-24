// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UserProfileResponseCitySettlementTypeEnum
    _$userProfileResponseCitySettlementTypeEnum_CITY =
    const UserProfileResponseCitySettlementTypeEnum._('CITY');
const UserProfileResponseCitySettlementTypeEnum
    _$userProfileResponseCitySettlementTypeEnum_TOWN =
    const UserProfileResponseCitySettlementTypeEnum._('TOWN');
const UserProfileResponseCitySettlementTypeEnum
    _$userProfileResponseCitySettlementTypeEnum_VILLAGE =
    const UserProfileResponseCitySettlementTypeEnum._('VILLAGE');
const UserProfileResponseCitySettlementTypeEnum
    _$userProfileResponseCitySettlementTypeEnum_SETTLEMENT =
    const UserProfileResponseCitySettlementTypeEnum._('SETTLEMENT');
const UserProfileResponseCitySettlementTypeEnum
    _$userProfileResponseCitySettlementTypeEnum_unknownDefaultOpenApi =
    const UserProfileResponseCitySettlementTypeEnum._('unknownDefaultOpenApi');

UserProfileResponseCitySettlementTypeEnum
    _$userProfileResponseCitySettlementTypeEnumValueOf(String name) {
  switch (name) {
    case 'CITY':
      return _$userProfileResponseCitySettlementTypeEnum_CITY;
    case 'TOWN':
      return _$userProfileResponseCitySettlementTypeEnum_TOWN;
    case 'VILLAGE':
      return _$userProfileResponseCitySettlementTypeEnum_VILLAGE;
    case 'SETTLEMENT':
      return _$userProfileResponseCitySettlementTypeEnum_SETTLEMENT;
    case 'unknownDefaultOpenApi':
      return _$userProfileResponseCitySettlementTypeEnum_unknownDefaultOpenApi;
    default:
      return _$userProfileResponseCitySettlementTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<UserProfileResponseCitySettlementTypeEnum>
    _$userProfileResponseCitySettlementTypeEnumValues = BuiltSet<
        UserProfileResponseCitySettlementTypeEnum>(const <UserProfileResponseCitySettlementTypeEnum>[
  _$userProfileResponseCitySettlementTypeEnum_CITY,
  _$userProfileResponseCitySettlementTypeEnum_TOWN,
  _$userProfileResponseCitySettlementTypeEnum_VILLAGE,
  _$userProfileResponseCitySettlementTypeEnum_SETTLEMENT,
  _$userProfileResponseCitySettlementTypeEnum_unknownDefaultOpenApi,
]);

Serializer<UserProfileResponseCitySettlementTypeEnum>
    _$userProfileResponseCitySettlementTypeEnumSerializer =
    _$UserProfileResponseCitySettlementTypeEnumSerializer();

class _$UserProfileResponseCitySettlementTypeEnumSerializer
    implements PrimitiveSerializer<UserProfileResponseCitySettlementTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CITY': 'CITY',
    'TOWN': 'TOWN',
    'VILLAGE': 'VILLAGE',
    'SETTLEMENT': 'SETTLEMENT',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CITY': 'CITY',
    'TOWN': 'TOWN',
    'VILLAGE': 'VILLAGE',
    'SETTLEMENT': 'SETTLEMENT',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[
    UserProfileResponseCitySettlementTypeEnum
  ];
  @override
  final String wireName = 'UserProfileResponseCitySettlementTypeEnum';

  @override
  Object serialize(Serializers serializers,
          UserProfileResponseCitySettlementTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  UserProfileResponseCitySettlementTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      UserProfileResponseCitySettlementTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

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
  final String? oblastId;
  @override
  final String? cityName;
  @override
  final String? oblastName;
  @override
  final String? districtName;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;
  @override
  final String? bio;
  @override
  final String? instagram;
  @override
  final String? professionalTitle;
  @override
  final bool? isActive;
  @override
  final bool? emailVerified;
  @override
  final String? salonId;
  @override
  final bool? hasMasterProfile;
  @override
  final UserProfileResponseCitySettlementTypeEnum? citySettlementType;
  @override
  final String? cityHromadaNameUk;

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
      this.oblastId,
      this.cityName,
      this.oblastName,
      this.districtName,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.bio,
      this.instagram,
      this.professionalTitle,
      this.isActive,
      this.emailVerified,
      this.salonId,
      this.hasMasterProfile,
      this.citySettlementType,
      this.cityHromadaNameUk})
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
        oblastId == other.oblastId &&
        cityName == other.cityName &&
        oblastName == other.oblastName &&
        districtName == other.districtName &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        bio == other.bio &&
        instagram == other.instagram &&
        professionalTitle == other.professionalTitle &&
        isActive == other.isActive &&
        emailVerified == other.emailVerified &&
        salonId == other.salonId &&
        hasMasterProfile == other.hasMasterProfile &&
        citySettlementType == other.citySettlementType &&
        cityHromadaNameUk == other.cityHromadaNameUk;
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
    _$hash = $jc(_$hash, oblastId.hashCode);
    _$hash = $jc(_$hash, cityName.hashCode);
    _$hash = $jc(_$hash, oblastName.hashCode);
    _$hash = $jc(_$hash, districtName.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, bio.hashCode);
    _$hash = $jc(_$hash, instagram.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jc(_$hash, isActive.hashCode);
    _$hash = $jc(_$hash, emailVerified.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, hasMasterProfile.hashCode);
    _$hash = $jc(_$hash, citySettlementType.hashCode);
    _$hash = $jc(_$hash, cityHromadaNameUk.hashCode);
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
          ..add('oblastId', oblastId)
          ..add('cityName', cityName)
          ..add('oblastName', oblastName)
          ..add('districtName', districtName)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('bio', bio)
          ..add('instagram', instagram)
          ..add('professionalTitle', professionalTitle)
          ..add('isActive', isActive)
          ..add('emailVerified', emailVerified)
          ..add('salonId', salonId)
          ..add('hasMasterProfile', hasMasterProfile)
          ..add('citySettlementType', citySettlementType)
          ..add('cityHromadaNameUk', cityHromadaNameUk))
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

  String? _oblastId;
  String? get oblastId => _$this._oblastId;
  set oblastId(String? oblastId) => _$this._oblastId = oblastId;

  String? _cityName;
  String? get cityName => _$this._cityName;
  set cityName(String? cityName) => _$this._cityName = cityName;

  String? _oblastName;
  String? get oblastName => _$this._oblastName;
  set oblastName(String? oblastName) => _$this._oblastName = oblastName;

  String? _districtName;
  String? get districtName => _$this._districtName;
  set districtName(String? districtName) => _$this._districtName = districtName;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  String? _bio;
  String? get bio => _$this._bio;
  set bio(String? bio) => _$this._bio = bio;

  String? _instagram;
  String? get instagram => _$this._instagram;
  set instagram(String? instagram) => _$this._instagram = instagram;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

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

  bool? _hasMasterProfile;
  bool? get hasMasterProfile => _$this._hasMasterProfile;
  set hasMasterProfile(bool? hasMasterProfile) =>
      _$this._hasMasterProfile = hasMasterProfile;

  UserProfileResponseCitySettlementTypeEnum? _citySettlementType;
  UserProfileResponseCitySettlementTypeEnum? get citySettlementType =>
      _$this._citySettlementType;
  set citySettlementType(
          UserProfileResponseCitySettlementTypeEnum? citySettlementType) =>
      _$this._citySettlementType = citySettlementType;

  String? _cityHromadaNameUk;
  String? get cityHromadaNameUk => _$this._cityHromadaNameUk;
  set cityHromadaNameUk(String? cityHromadaNameUk) =>
      _$this._cityHromadaNameUk = cityHromadaNameUk;

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
      _oblastId = $v.oblastId;
      _cityName = $v.cityName;
      _oblastName = $v.oblastName;
      _districtName = $v.districtName;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _bio = $v.bio;
      _instagram = $v.instagram;
      _professionalTitle = $v.professionalTitle;
      _isActive = $v.isActive;
      _emailVerified = $v.emailVerified;
      _salonId = $v.salonId;
      _hasMasterProfile = $v.hasMasterProfile;
      _citySettlementType = $v.citySettlementType;
      _cityHromadaNameUk = $v.cityHromadaNameUk;
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
          oblastId: oblastId,
          cityName: cityName,
          oblastName: oblastName,
          districtName: districtName,
          street: street,
          buildingNo: buildingNo,
          locationNote: locationNote,
          bio: bio,
          instagram: instagram,
          professionalTitle: professionalTitle,
          isActive: isActive,
          emailVerified: emailVerified,
          salonId: salonId,
          hasMasterProfile: hasMasterProfile,
          citySettlementType: citySettlementType,
          cityHromadaNameUk: cityHromadaNameUk,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
