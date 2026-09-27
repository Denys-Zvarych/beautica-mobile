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
const MasterDetailResponseMasterTypeEnum
    _$masterDetailResponseMasterTypeEnum_unknownDefaultOpenApi =
    const MasterDetailResponseMasterTypeEnum._('unknownDefaultOpenApi');

MasterDetailResponseMasterTypeEnum _$masterDetailResponseMasterTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'SALON_MASTER':
      return _$masterDetailResponseMasterTypeEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$masterDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;
    case 'SALON_OWNER':
      return _$masterDetailResponseMasterTypeEnum_SALON_OWNER;
    case 'unknownDefaultOpenApi':
      return _$masterDetailResponseMasterTypeEnum_unknownDefaultOpenApi;
    default:
      return _$masterDetailResponseMasterTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<MasterDetailResponseMasterTypeEnum>
    _$masterDetailResponseMasterTypeEnumValues = BuiltSet<
        MasterDetailResponseMasterTypeEnum>(const <MasterDetailResponseMasterTypeEnum>[
  _$masterDetailResponseMasterTypeEnum_SALON_MASTER,
  _$masterDetailResponseMasterTypeEnum_INDEPENDENT_MASTER,
  _$masterDetailResponseMasterTypeEnum_SALON_OWNER,
  _$masterDetailResponseMasterTypeEnum_unknownDefaultOpenApi,
]);

const MasterDetailResponseCitySettlementTypeEnum
    _$masterDetailResponseCitySettlementTypeEnum_CITY =
    const MasterDetailResponseCitySettlementTypeEnum._('CITY');
const MasterDetailResponseCitySettlementTypeEnum
    _$masterDetailResponseCitySettlementTypeEnum_TOWN =
    const MasterDetailResponseCitySettlementTypeEnum._('TOWN');
const MasterDetailResponseCitySettlementTypeEnum
    _$masterDetailResponseCitySettlementTypeEnum_VILLAGE =
    const MasterDetailResponseCitySettlementTypeEnum._('VILLAGE');
const MasterDetailResponseCitySettlementTypeEnum
    _$masterDetailResponseCitySettlementTypeEnum_SETTLEMENT =
    const MasterDetailResponseCitySettlementTypeEnum._('SETTLEMENT');
const MasterDetailResponseCitySettlementTypeEnum
    _$masterDetailResponseCitySettlementTypeEnum_unknownDefaultOpenApi =
    const MasterDetailResponseCitySettlementTypeEnum._('unknownDefaultOpenApi');

MasterDetailResponseCitySettlementTypeEnum
    _$masterDetailResponseCitySettlementTypeEnumValueOf(String name) {
  switch (name) {
    case 'CITY':
      return _$masterDetailResponseCitySettlementTypeEnum_CITY;
    case 'TOWN':
      return _$masterDetailResponseCitySettlementTypeEnum_TOWN;
    case 'VILLAGE':
      return _$masterDetailResponseCitySettlementTypeEnum_VILLAGE;
    case 'SETTLEMENT':
      return _$masterDetailResponseCitySettlementTypeEnum_SETTLEMENT;
    case 'unknownDefaultOpenApi':
      return _$masterDetailResponseCitySettlementTypeEnum_unknownDefaultOpenApi;
    default:
      return _$masterDetailResponseCitySettlementTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<MasterDetailResponseCitySettlementTypeEnum>
    _$masterDetailResponseCitySettlementTypeEnumValues = BuiltSet<
        MasterDetailResponseCitySettlementTypeEnum>(const <MasterDetailResponseCitySettlementTypeEnum>[
  _$masterDetailResponseCitySettlementTypeEnum_CITY,
  _$masterDetailResponseCitySettlementTypeEnum_TOWN,
  _$masterDetailResponseCitySettlementTypeEnum_VILLAGE,
  _$masterDetailResponseCitySettlementTypeEnum_SETTLEMENT,
  _$masterDetailResponseCitySettlementTypeEnum_unknownDefaultOpenApi,
]);

Serializer<MasterDetailResponseMasterTypeEnum>
    _$masterDetailResponseMasterTypeEnumSerializer =
    _$MasterDetailResponseMasterTypeEnumSerializer();
Serializer<MasterDetailResponseCitySettlementTypeEnum>
    _$masterDetailResponseCitySettlementTypeEnumSerializer =
    _$MasterDetailResponseCitySettlementTypeEnumSerializer();

class _$MasterDetailResponseMasterTypeEnumSerializer
    implements PrimitiveSerializer<MasterDetailResponseMasterTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
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

class _$MasterDetailResponseCitySettlementTypeEnumSerializer
    implements PrimitiveSerializer<MasterDetailResponseCitySettlementTypeEnum> {
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
    MasterDetailResponseCitySettlementTypeEnum
  ];
  @override
  final String wireName = 'MasterDetailResponseCitySettlementTypeEnum';

  @override
  Object serialize(Serializers serializers,
          MasterDetailResponseCitySettlementTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MasterDetailResponseCitySettlementTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MasterDetailResponseCitySettlementTypeEnum.valueOf(
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
  final String? phoneNumber;
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
  final String? instagram;
  @override
  final String? professionalTitle;
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
  final String? cityId;
  @override
  final String? oblastId;
  @override
  final String? districtId;
  @override
  final int? bookingsThisMonth;
  @override
  final String? region;
  @override
  final MasterDetailResponseCitySettlementTypeEnum? citySettlementType;
  @override
  final String? cityHromadaNameUk;

  factory _$MasterDetailResponse(
          [void Function(MasterDetailResponseBuilder)? updates]) =>
      (MasterDetailResponseBuilder()..update(updates))._build();

  _$MasterDetailResponse._(
      {this.masterId,
      this.firstName,
      this.lastName,
      this.phoneNumber,
      this.city,
      this.street,
      this.buildingNo,
      this.locationNote,
      this.bio,
      this.instagram,
      this.professionalTitle,
      this.avatarUrl,
      this.avgRating,
      this.reviewCount,
      this.masterType,
      this.salon,
      this.workingHours,
      this.cityId,
      this.oblastId,
      this.districtId,
      this.bookingsThisMonth,
      this.region,
      this.citySettlementType,
      this.cityHromadaNameUk})
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
        phoneNumber == other.phoneNumber &&
        city == other.city &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote &&
        bio == other.bio &&
        instagram == other.instagram &&
        professionalTitle == other.professionalTitle &&
        avatarUrl == other.avatarUrl &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        masterType == other.masterType &&
        salon == other.salon &&
        workingHours == other.workingHours &&
        cityId == other.cityId &&
        oblastId == other.oblastId &&
        districtId == other.districtId &&
        bookingsThisMonth == other.bookingsThisMonth &&
        region == other.region &&
        citySettlementType == other.citySettlementType &&
        cityHromadaNameUk == other.cityHromadaNameUk;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, city.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, bio.hashCode);
    _$hash = $jc(_$hash, instagram.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, masterType.hashCode);
    _$hash = $jc(_$hash, salon.hashCode);
    _$hash = $jc(_$hash, workingHours.hashCode);
    _$hash = $jc(_$hash, cityId.hashCode);
    _$hash = $jc(_$hash, oblastId.hashCode);
    _$hash = $jc(_$hash, districtId.hashCode);
    _$hash = $jc(_$hash, bookingsThisMonth.hashCode);
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, citySettlementType.hashCode);
    _$hash = $jc(_$hash, cityHromadaNameUk.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterDetailResponse')
          ..add('masterId', masterId)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber)
          ..add('city', city)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote)
          ..add('bio', bio)
          ..add('instagram', instagram)
          ..add('professionalTitle', professionalTitle)
          ..add('avatarUrl', avatarUrl)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('masterType', masterType)
          ..add('salon', salon)
          ..add('workingHours', workingHours)
          ..add('cityId', cityId)
          ..add('oblastId', oblastId)
          ..add('districtId', districtId)
          ..add('bookingsThisMonth', bookingsThisMonth)
          ..add('region', region)
          ..add('citySettlementType', citySettlementType)
          ..add('cityHromadaNameUk', cityHromadaNameUk))
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

  String? _phoneNumber;
  String? get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String? phoneNumber) => _$this._phoneNumber = phoneNumber;

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

  String? _instagram;
  String? get instagram => _$this._instagram;
  set instagram(String? instagram) => _$this._instagram = instagram;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

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

  String? _cityId;
  String? get cityId => _$this._cityId;
  set cityId(String? cityId) => _$this._cityId = cityId;

  String? _oblastId;
  String? get oblastId => _$this._oblastId;
  set oblastId(String? oblastId) => _$this._oblastId = oblastId;

  String? _districtId;
  String? get districtId => _$this._districtId;
  set districtId(String? districtId) => _$this._districtId = districtId;

  int? _bookingsThisMonth;
  int? get bookingsThisMonth => _$this._bookingsThisMonth;
  set bookingsThisMonth(int? bookingsThisMonth) =>
      _$this._bookingsThisMonth = bookingsThisMonth;

  String? _region;
  String? get region => _$this._region;
  set region(String? region) => _$this._region = region;

  MasterDetailResponseCitySettlementTypeEnum? _citySettlementType;
  MasterDetailResponseCitySettlementTypeEnum? get citySettlementType =>
      _$this._citySettlementType;
  set citySettlementType(
          MasterDetailResponseCitySettlementTypeEnum? citySettlementType) =>
      _$this._citySettlementType = citySettlementType;

  String? _cityHromadaNameUk;
  String? get cityHromadaNameUk => _$this._cityHromadaNameUk;
  set cityHromadaNameUk(String? cityHromadaNameUk) =>
      _$this._cityHromadaNameUk = cityHromadaNameUk;

  MasterDetailResponseBuilder() {
    MasterDetailResponse._defaults(this);
  }

  MasterDetailResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _phoneNumber = $v.phoneNumber;
      _city = $v.city;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _bio = $v.bio;
      _instagram = $v.instagram;
      _professionalTitle = $v.professionalTitle;
      _avatarUrl = $v.avatarUrl;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _masterType = $v.masterType;
      _salon = $v.salon?.toBuilder();
      _workingHours = $v.workingHours?.toBuilder();
      _cityId = $v.cityId;
      _oblastId = $v.oblastId;
      _districtId = $v.districtId;
      _bookingsThisMonth = $v.bookingsThisMonth;
      _region = $v.region;
      _citySettlementType = $v.citySettlementType;
      _cityHromadaNameUk = $v.cityHromadaNameUk;
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
            phoneNumber: phoneNumber,
            city: city,
            street: street,
            buildingNo: buildingNo,
            locationNote: locationNote,
            bio: bio,
            instagram: instagram,
            professionalTitle: professionalTitle,
            avatarUrl: avatarUrl,
            avgRating: avgRating,
            reviewCount: reviewCount,
            masterType: masterType,
            salon: _salon?.build(),
            workingHours: _workingHours?.build(),
            cityId: cityId,
            oblastId: oblastId,
            districtId: districtId,
            bookingsThisMonth: bookingsThisMonth,
            region: region,
            citySettlementType: citySettlementType,
            cityHromadaNameUk: cityHromadaNameUk,
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
