// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_detail_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MasterDetailResponseMasterTypeEnum
    _$masterDetailResponseMasterTypeEnum_SALON_MASTER =
    const MasterDetailResponseMasterTypeEnum._('SALON_MASTER');
const MasterDetailResponseMasterTypeEnum
    _$masterDetailResponseMasterTypeEnum_INDEPENDENT_MASTER =
    const MasterDetailResponseMasterTypeEnum._('INDEPENDENT_MASTER');
const MasterDetailResponseMasterTypeEnum
    _$masterDetailResponseMasterTypeEnum_SALON_OWNER =
    const MasterDetailResponseMasterTypeEnum._('SALON_OWNER');

MasterDetailResponseMasterTypeEnum _$masterDetailResponseMasterTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'SALON_MASTER':
      return _$masterDetailResponseMasterTypeEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$masterDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;
    case 'SALON_OWNER':
      return _$masterDetailResponseMasterTypeEnum_SALON_OWNER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MasterDetailResponseMasterTypeEnum>
    _$masterDetailResponseMasterTypeEnumValues = BuiltSet<
        MasterDetailResponseMasterTypeEnum>(const <MasterDetailResponseMasterTypeEnum>[
  _$masterDetailResponseMasterTypeEnum_SALON_MASTER,
  _$masterDetailResponseMasterTypeEnum_INDEPENDENT_MASTER,
  _$masterDetailResponseMasterTypeEnum_SALON_OWNER,
]);

Serializer<MasterDetailResponseMasterTypeEnum>
    _$masterDetailResponseMasterTypeEnumSerializer =
    _$MasterDetailResponseMasterTypeEnumSerializer();

class _$MasterDetailResponseMasterTypeEnumSerializer
    implements PrimitiveSerializer<MasterDetailResponseMasterTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
  };

  @override
  final Iterable<Type> types = const <Type>[MasterDetailResponseMasterTypeEnum];
  @override
  final String wireName = 'MasterDetailResponseMasterTypeEnum';

  @override
  Object serialize(
          Serializers serializers, MasterDetailResponseMasterTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MasterDetailResponseMasterTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MasterDetailResponseMasterTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$MasterDetailResponse extends MasterDetailResponse {
  @override
  final String? masterId;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? city;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;
  @override
  final String? bio;
  @override
  final String? avatarUrl;
  @override
  final num? avgRating;
  @override
  final int? reviewCount;
  @override
  final MasterDetailResponseMasterTypeEnum? masterType;
  @override
  final PublicSalonResponse? salon;
  @override
  final BuiltList<WorkingHoursResponse>? workingHours;
  @override
  final String? phoneNumber;

  factory _$MasterDetailResponse(
          [void Function(MasterDetailResponseBuilder)? updates]) =>
      (MasterDetailResponseBuilder()..update(updates))._build();

  _$MasterDetailResponse._(
      {this.masterId,
      this.firstName,
      this.lastName,
      this.city,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.bio,
      this.avatarUrl,
      this.avgRating,
      this.reviewCount,
      this.masterType,
      this.salon,
      this.workingHours,
      this.phoneNumber})
      : super._();
  @override
  MasterDetailResponse rebuild(
          void Function(MasterDetailResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterDetailResponseBuilder toBuilder() =>
      MasterDetailResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterDetailResponse &&
        masterId == other.masterId &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        city == other.city &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        bio == other.bio &&
        avatarUrl == other.avatarUrl &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        masterType == other.masterType &&
        salon == other.salon &&
        workingHours == other.workingHours &&
        phoneNumber == other.phoneNumber;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, city.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, bio.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, masterType.hashCode);
    _$hash = $jc(_$hash, salon.hashCode);
    _$hash = $jc(_$hash, workingHours.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterDetailResponse')
          ..add('masterId', masterId)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('city', city)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('bio', bio)
          ..add('avatarUrl', avatarUrl)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('masterType', masterType)
          ..add('salon', salon)
          ..add('workingHours', workingHours)
          ..add('phoneNumber', phoneNumber))
        .toString();
  }
}

class MasterDetailResponseBuilder
    implements Builder<MasterDetailResponse, MasterDetailResponseBuilder> {
  _$MasterDetailResponse? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _city;
  String? get city => _$this._city;
  set city(String? city) => _$this._city = city;

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

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  MasterDetailResponseMasterTypeEnum? _masterType;
  MasterDetailResponseMasterTypeEnum? get masterType => _$this._masterType;
  set masterType(MasterDetailResponseMasterTypeEnum? masterType) =>
      _$this._masterType = masterType;

  PublicSalonResponseBuilder? _salon;
  PublicSalonResponseBuilder get salon =>
      _$this._salon ??= PublicSalonResponseBuilder();
  set salon(PublicSalonResponseBuilder? salon) => _$this._salon = salon;

  ListBuilder<WorkingHoursResponse>? _workingHours;
  ListBuilder<WorkingHoursResponse> get workingHours =>
      _$this._workingHours ??= ListBuilder<WorkingHoursResponse>();
  set workingHours(ListBuilder<WorkingHoursResponse>? workingHours) =>
      _$this._workingHours = workingHours;

  String? _phoneNumber;
  String? get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String? phoneNumber) => _$this._phoneNumber = phoneNumber;

  MasterDetailResponseBuilder() {
    MasterDetailResponse._defaults(this);
  }

  MasterDetailResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _city = $v.city;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _bio = $v.bio;
      _avatarUrl = $v.avatarUrl;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _masterType = $v.masterType;
      _salon = $v.salon?.toBuilder();
      _workingHours = $v.workingHours?.toBuilder();
      _phoneNumber = $v.phoneNumber;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MasterDetailResponse other) {
    _$v = other as _$MasterDetailResponse;
  }

  @override
  void update(void Function(MasterDetailResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterDetailResponse build() => _build();

  _$MasterDetailResponse _build() {
    _$MasterDetailResponse _$result;
    try {
      _$result = _$v ??
          _$MasterDetailResponse._(
            masterId: masterId,
            firstName: firstName,
            lastName: lastName,
            city: city,
            street: street,
            buildingNo: buildingNo,
            locationNote: locationNote,
            bio: bio,
            avatarUrl: avatarUrl,
            avgRating: avgRating,
            reviewCount: reviewCount,
            masterType: masterType,
            salon: _salon?.build(),
            workingHours: _workingHours?.build(),
            phoneNumber: phoneNumber,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'salon';
        _salon?.build();
        _$failedField = 'workingHours';
        _workingHours?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MasterDetailResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
