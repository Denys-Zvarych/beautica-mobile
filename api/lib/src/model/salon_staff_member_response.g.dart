// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_staff_member_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SalonStaffMemberResponseRoleEnum
    _$salonStaffMemberResponseRoleEnum_CLIENT =
    const SalonStaffMemberResponseRoleEnum._('CLIENT');
const SalonStaffMemberResponseRoleEnum
    _$salonStaffMemberResponseRoleEnum_SALON_OWNER =
    const SalonStaffMemberResponseRoleEnum._('SALON_OWNER');
const SalonStaffMemberResponseRoleEnum
    _$salonStaffMemberResponseRoleEnum_SALON_ADMIN =
    const SalonStaffMemberResponseRoleEnum._('SALON_ADMIN');
const SalonStaffMemberResponseRoleEnum
    _$salonStaffMemberResponseRoleEnum_SALON_MASTER =
    const SalonStaffMemberResponseRoleEnum._('SALON_MASTER');
const SalonStaffMemberResponseRoleEnum
    _$salonStaffMemberResponseRoleEnum_INDEPENDENT_MASTER =
    const SalonStaffMemberResponseRoleEnum._('INDEPENDENT_MASTER');

SalonStaffMemberResponseRoleEnum _$salonStaffMemberResponseRoleEnumValueOf(
    String name) {
  switch (name) {
    case 'CLIENT':
      return _$salonStaffMemberResponseRoleEnum_CLIENT;
    case 'SALON_OWNER':
      return _$salonStaffMemberResponseRoleEnum_SALON_OWNER;
    case 'SALON_ADMIN':
      return _$salonStaffMemberResponseRoleEnum_SALON_ADMIN;
    case 'SALON_MASTER':
      return _$salonStaffMemberResponseRoleEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$salonStaffMemberResponseRoleEnum_INDEPENDENT_MASTER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<SalonStaffMemberResponseRoleEnum>
    _$salonStaffMemberResponseRoleEnumValues = BuiltSet<
        SalonStaffMemberResponseRoleEnum>(const <SalonStaffMemberResponseRoleEnum>[
  _$salonStaffMemberResponseRoleEnum_CLIENT,
  _$salonStaffMemberResponseRoleEnum_SALON_OWNER,
  _$salonStaffMemberResponseRoleEnum_SALON_ADMIN,
  _$salonStaffMemberResponseRoleEnum_SALON_MASTER,
  _$salonStaffMemberResponseRoleEnum_INDEPENDENT_MASTER,
]);

Serializer<SalonStaffMemberResponseRoleEnum>
    _$salonStaffMemberResponseRoleEnumSerializer =
    _$SalonStaffMemberResponseRoleEnumSerializer();

class _$SalonStaffMemberResponseRoleEnumSerializer
    implements PrimitiveSerializer<SalonStaffMemberResponseRoleEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CLIENT': 'CLIENT',
    'SALON_OWNER': 'SALON_OWNER',
    'SALON_ADMIN': 'SALON_ADMIN',
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CLIENT': 'CLIENT',
    'SALON_OWNER': 'SALON_OWNER',
    'SALON_ADMIN': 'SALON_ADMIN',
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
  };

  @override
  final Iterable<Type> types = const <Type>[SalonStaffMemberResponseRoleEnum];
  @override
  final String wireName = 'SalonStaffMemberResponseRoleEnum';

  @override
  Object serialize(
          Serializers serializers, SalonStaffMemberResponseRoleEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  SalonStaffMemberResponseRoleEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      SalonStaffMemberResponseRoleEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$SalonStaffMemberResponse extends SalonStaffMemberResponse {
  @override
  final String? userId;
  @override
  final String? masterId;
  @override
  final SalonStaffMemberResponseRoleEnum? role;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? professionalTitle;
  @override
  final String? avatarUrl;
  @override
  final String? phoneNumber;
  @override
  final String? instagram;
  @override
  final String? bio;
  @override
  final num? avgRating;
  @override
  final int? reviewCount;
  @override
  final int? serviceCount;

  factory _$SalonStaffMemberResponse(
          [void Function(SalonStaffMemberResponseBuilder)? updates]) =>
      (SalonStaffMemberResponseBuilder()..update(updates))._build();

  _$SalonStaffMemberResponse._(
      {this.userId,
      this.masterId,
      this.role,
      this.firstName,
      this.lastName,
      this.professionalTitle,
      this.avatarUrl,
      this.phoneNumber,
      this.instagram,
      this.bio,
      this.avgRating,
      this.reviewCount,
      this.serviceCount})
      : super._();
  @override
  SalonStaffMemberResponse rebuild(
          void Function(SalonStaffMemberResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonStaffMemberResponseBuilder toBuilder() =>
      SalonStaffMemberResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonStaffMemberResponse &&
        userId == other.userId &&
        masterId == other.masterId &&
        role == other.role &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        professionalTitle == other.professionalTitle &&
        avatarUrl == other.avatarUrl &&
        phoneNumber == other.phoneNumber &&
        instagram == other.instagram &&
        bio == other.bio &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        serviceCount == other.serviceCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, instagram.hashCode);
    _$hash = $jc(_$hash, bio.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, serviceCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonStaffMemberResponse')
          ..add('userId', userId)
          ..add('masterId', masterId)
          ..add('role', role)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('professionalTitle', professionalTitle)
          ..add('avatarUrl', avatarUrl)
          ..add('phoneNumber', phoneNumber)
          ..add('instagram', instagram)
          ..add('bio', bio)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('serviceCount', serviceCount))
        .toString();
  }
}

class SalonStaffMemberResponseBuilder
    implements
        Builder<SalonStaffMemberResponse, SalonStaffMemberResponseBuilder> {
  _$SalonStaffMemberResponse? _$v;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  SalonStaffMemberResponseRoleEnum? _role;
  SalonStaffMemberResponseRoleEnum? get role => _$this._role;
  set role(SalonStaffMemberResponseRoleEnum? role) => _$this._role = role;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  String? _phoneNumber;
  String? get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String? phoneNumber) => _$this._phoneNumber = phoneNumber;

  String? _instagram;
  String? get instagram => _$this._instagram;
  set instagram(String? instagram) => _$this._instagram = instagram;

  String? _bio;
  String? get bio => _$this._bio;
  set bio(String? bio) => _$this._bio = bio;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  int? _serviceCount;
  int? get serviceCount => _$this._serviceCount;
  set serviceCount(int? serviceCount) => _$this._serviceCount = serviceCount;

  SalonStaffMemberResponseBuilder() {
    SalonStaffMemberResponse._defaults(this);
  }

  SalonStaffMemberResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _userId = $v.userId;
      _masterId = $v.masterId;
      _role = $v.role;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _professionalTitle = $v.professionalTitle;
      _avatarUrl = $v.avatarUrl;
      _phoneNumber = $v.phoneNumber;
      _instagram = $v.instagram;
      _bio = $v.bio;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _serviceCount = $v.serviceCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonStaffMemberResponse other) {
    _$v = other as _$SalonStaffMemberResponse;
  }

  @override
  void update(void Function(SalonStaffMemberResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonStaffMemberResponse build() => _build();

  _$SalonStaffMemberResponse _build() {
    final _$result = _$v ??
        _$SalonStaffMemberResponse._(
          userId: userId,
          masterId: masterId,
          role: role,
          firstName: firstName,
          lastName: lastName,
          professionalTitle: professionalTitle,
          avatarUrl: avatarUrl,
          phoneNumber: phoneNumber,
          instagram: instagram,
          bio: bio,
          avgRating: avgRating,
          reviewCount: reviewCount,
          serviceCount: serviceCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
