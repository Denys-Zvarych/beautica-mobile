// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment_detail_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AppointmentDetailResponseStatusEnum
    _$appointmentDetailResponseStatusEnum_CONFIRMED =
    const AppointmentDetailResponseStatusEnum._('CONFIRMED');
const AppointmentDetailResponseStatusEnum
    _$appointmentDetailResponseStatusEnum_DECLINED =
    const AppointmentDetailResponseStatusEnum._('DECLINED');
const AppointmentDetailResponseStatusEnum
    _$appointmentDetailResponseStatusEnum_COMPLETED =
    const AppointmentDetailResponseStatusEnum._('COMPLETED');
const AppointmentDetailResponseStatusEnum
    _$appointmentDetailResponseStatusEnum_NOT_COMPLETED =
    const AppointmentDetailResponseStatusEnum._('NOT_COMPLETED');
const AppointmentDetailResponseStatusEnum
    _$appointmentDetailResponseStatusEnum_CANCELLED =
    const AppointmentDetailResponseStatusEnum._('CANCELLED');

AppointmentDetailResponseStatusEnum
    _$appointmentDetailResponseStatusEnumValueOf(String name) {
  switch (name) {
    case 'CONFIRMED':
      return _$appointmentDetailResponseStatusEnum_CONFIRMED;
    case 'DECLINED':
      return _$appointmentDetailResponseStatusEnum_DECLINED;
    case 'COMPLETED':
      return _$appointmentDetailResponseStatusEnum_COMPLETED;
    case 'NOT_COMPLETED':
      return _$appointmentDetailResponseStatusEnum_NOT_COMPLETED;
    case 'CANCELLED':
      return _$appointmentDetailResponseStatusEnum_CANCELLED;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AppointmentDetailResponseStatusEnum>
    _$appointmentDetailResponseStatusEnumValues = BuiltSet<
        AppointmentDetailResponseStatusEnum>(const <AppointmentDetailResponseStatusEnum>[
  _$appointmentDetailResponseStatusEnum_CONFIRMED,
  _$appointmentDetailResponseStatusEnum_DECLINED,
  _$appointmentDetailResponseStatusEnum_COMPLETED,
  _$appointmentDetailResponseStatusEnum_NOT_COMPLETED,
  _$appointmentDetailResponseStatusEnum_CANCELLED,
]);

const AppointmentDetailResponseMasterTypeEnum
    _$appointmentDetailResponseMasterTypeEnum_CLIENT =
    const AppointmentDetailResponseMasterTypeEnum._('CLIENT');
const AppointmentDetailResponseMasterTypeEnum
    _$appointmentDetailResponseMasterTypeEnum_SALON_OWNER =
    const AppointmentDetailResponseMasterTypeEnum._('SALON_OWNER');
const AppointmentDetailResponseMasterTypeEnum
    _$appointmentDetailResponseMasterTypeEnum_SALON_ADMIN =
    const AppointmentDetailResponseMasterTypeEnum._('SALON_ADMIN');
const AppointmentDetailResponseMasterTypeEnum
    _$appointmentDetailResponseMasterTypeEnum_SALON_MASTER =
    const AppointmentDetailResponseMasterTypeEnum._('SALON_MASTER');
const AppointmentDetailResponseMasterTypeEnum
    _$appointmentDetailResponseMasterTypeEnum_INDEPENDENT_MASTER =
    const AppointmentDetailResponseMasterTypeEnum._('INDEPENDENT_MASTER');

AppointmentDetailResponseMasterTypeEnum
    _$appointmentDetailResponseMasterTypeEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT':
      return _$appointmentDetailResponseMasterTypeEnum_CLIENT;
    case 'SALON_OWNER':
      return _$appointmentDetailResponseMasterTypeEnum_SALON_OWNER;
    case 'SALON_ADMIN':
      return _$appointmentDetailResponseMasterTypeEnum_SALON_ADMIN;
    case 'SALON_MASTER':
      return _$appointmentDetailResponseMasterTypeEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$appointmentDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AppointmentDetailResponseMasterTypeEnum>
    _$appointmentDetailResponseMasterTypeEnumValues = BuiltSet<
        AppointmentDetailResponseMasterTypeEnum>(const <AppointmentDetailResponseMasterTypeEnum>[
  _$appointmentDetailResponseMasterTypeEnum_CLIENT,
  _$appointmentDetailResponseMasterTypeEnum_SALON_OWNER,
  _$appointmentDetailResponseMasterTypeEnum_SALON_ADMIN,
  _$appointmentDetailResponseMasterTypeEnum_SALON_MASTER,
  _$appointmentDetailResponseMasterTypeEnum_INDEPENDENT_MASTER,
]);

Serializer<AppointmentDetailResponseStatusEnum>
    _$appointmentDetailResponseStatusEnumSerializer =
    _$AppointmentDetailResponseStatusEnumSerializer();
Serializer<AppointmentDetailResponseMasterTypeEnum>
    _$appointmentDetailResponseMasterTypeEnumSerializer =
    _$AppointmentDetailResponseMasterTypeEnumSerializer();

class _$AppointmentDetailResponseStatusEnumSerializer
    implements PrimitiveSerializer<AppointmentDetailResponseStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
  };

  @override
  final Iterable<Type> types = const <Type>[
    AppointmentDetailResponseStatusEnum
  ];
  @override
  final String wireName = 'AppointmentDetailResponseStatusEnum';

  @override
  Object serialize(
          Serializers serializers, AppointmentDetailResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AppointmentDetailResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AppointmentDetailResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AppointmentDetailResponseMasterTypeEnumSerializer
    implements PrimitiveSerializer<AppointmentDetailResponseMasterTypeEnum> {
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
  final Iterable<Type> types = const <Type>[
    AppointmentDetailResponseMasterTypeEnum
  ];
  @override
  final String wireName = 'AppointmentDetailResponseMasterTypeEnum';

  @override
  Object serialize(Serializers serializers,
          AppointmentDetailResponseMasterTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AppointmentDetailResponseMasterTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AppointmentDetailResponseMasterTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AppointmentDetailResponse extends AppointmentDetailResponse {
  @override
  final String? id;
  @override
  final AppointmentDetailResponseStatusEnum? status;
  @override
  final String? masterId;
  @override
  final String? masterFirstName;
  @override
  final String? masterLastName;
  @override
  final String? masterProfessionalTitle;
  @override
  final String? masterAvatarUrl;
  @override
  final AppointmentDetailResponseMasterTypeEnum? masterType;
  @override
  final String? salonName;
  @override
  final DateTime? startsAt;
  @override
  final DateTime? endsAt;
  @override
  final int? totalDurationMinutes;
  @override
  final num? totalPrice;
  @override
  final num? totalPriceMax;
  @override
  final String? clientComment;
  @override
  final DateTime? createdAt;
  @override
  final BuiltList<AppointmentItemResponse>? items;
  @override
  final String? providerComment;
  @override
  final String? clientCancellationNote;
  @override
  final String? cityLabel;
  @override
  final String? districtLabel;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;

  factory _$AppointmentDetailResponse(
          [void Function(AppointmentDetailResponseBuilder)? updates]) =>
      (AppointmentDetailResponseBuilder()..update(updates))._build();

  _$AppointmentDetailResponse._(
      {this.id,
      this.status,
      this.masterId,
      this.masterFirstName,
      this.masterLastName,
      this.masterProfessionalTitle,
      this.masterAvatarUrl,
      this.masterType,
      this.salonName,
      this.startsAt,
      this.endsAt,
      this.totalDurationMinutes,
      this.totalPrice,
      this.totalPriceMax,
      this.clientComment,
      this.createdAt,
      this.items,
      this.providerComment,
      this.clientCancellationNote,
      this.cityLabel,
      this.districtLabel,
      this.street,
      this.buildingNo,
      this.locationNote})
      : super._();
  @override
  AppointmentDetailResponse rebuild(
          void Function(AppointmentDetailResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppointmentDetailResponseBuilder toBuilder() =>
      AppointmentDetailResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppointmentDetailResponse &&
        id == other.id &&
        status == other.status &&
        masterId == other.masterId &&
        masterFirstName == other.masterFirstName &&
        masterLastName == other.masterLastName &&
        masterProfessionalTitle == other.masterProfessionalTitle &&
        masterAvatarUrl == other.masterAvatarUrl &&
        masterType == other.masterType &&
        salonName == other.salonName &&
        startsAt == other.startsAt &&
        endsAt == other.endsAt &&
        totalDurationMinutes == other.totalDurationMinutes &&
        totalPrice == other.totalPrice &&
        totalPriceMax == other.totalPriceMax &&
        clientComment == other.clientComment &&
        createdAt == other.createdAt &&
        items == other.items &&
        providerComment == other.providerComment &&
        clientCancellationNote == other.clientCancellationNote &&
        cityLabel == other.cityLabel &&
        districtLabel == other.districtLabel &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterFirstName.hashCode);
    _$hash = $jc(_$hash, masterLastName.hashCode);
    _$hash = $jc(_$hash, masterProfessionalTitle.hashCode);
    _$hash = $jc(_$hash, masterAvatarUrl.hashCode);
    _$hash = $jc(_$hash, masterType.hashCode);
    _$hash = $jc(_$hash, salonName.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, endsAt.hashCode);
    _$hash = $jc(_$hash, totalDurationMinutes.hashCode);
    _$hash = $jc(_$hash, totalPrice.hashCode);
    _$hash = $jc(_$hash, totalPriceMax.hashCode);
    _$hash = $jc(_$hash, clientComment.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, providerComment.hashCode);
    _$hash = $jc(_$hash, clientCancellationNote.hashCode);
    _$hash = $jc(_$hash, cityLabel.hashCode);
    _$hash = $jc(_$hash, districtLabel.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppointmentDetailResponse')
          ..add('id', id)
          ..add('status', status)
          ..add('masterId', masterId)
          ..add('masterFirstName', masterFirstName)
          ..add('masterLastName', masterLastName)
          ..add('masterProfessionalTitle', masterProfessionalTitle)
          ..add('masterAvatarUrl', masterAvatarUrl)
          ..add('masterType', masterType)
          ..add('salonName', salonName)
          ..add('startsAt', startsAt)
          ..add('endsAt', endsAt)
          ..add('totalDurationMinutes', totalDurationMinutes)
          ..add('totalPrice', totalPrice)
          ..add('totalPriceMax', totalPriceMax)
          ..add('clientComment', clientComment)
          ..add('createdAt', createdAt)
          ..add('items', items)
          ..add('providerComment', providerComment)
          ..add('clientCancellationNote', clientCancellationNote)
          ..add('cityLabel', cityLabel)
          ..add('districtLabel', districtLabel)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote))
        .toString();
  }
}

class AppointmentDetailResponseBuilder
    implements
        Builder<AppointmentDetailResponse, AppointmentDetailResponseBuilder> {
  _$AppointmentDetailResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  AppointmentDetailResponseStatusEnum? _status;
  AppointmentDetailResponseStatusEnum? get status => _$this._status;
  set status(AppointmentDetailResponseStatusEnum? status) =>
      _$this._status = status;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterFirstName;
  String? get masterFirstName => _$this._masterFirstName;
  set masterFirstName(String? masterFirstName) =>
      _$this._masterFirstName = masterFirstName;

  String? _masterLastName;
  String? get masterLastName => _$this._masterLastName;
  set masterLastName(String? masterLastName) =>
      _$this._masterLastName = masterLastName;

  String? _masterProfessionalTitle;
  String? get masterProfessionalTitle => _$this._masterProfessionalTitle;
  set masterProfessionalTitle(String? masterProfessionalTitle) =>
      _$this._masterProfessionalTitle = masterProfessionalTitle;

  String? _masterAvatarUrl;
  String? get masterAvatarUrl => _$this._masterAvatarUrl;
  set masterAvatarUrl(String? masterAvatarUrl) =>
      _$this._masterAvatarUrl = masterAvatarUrl;

  AppointmentDetailResponseMasterTypeEnum? _masterType;
  AppointmentDetailResponseMasterTypeEnum? get masterType => _$this._masterType;
  set masterType(AppointmentDetailResponseMasterTypeEnum? masterType) =>
      _$this._masterType = masterType;

  String? _salonName;
  String? get salonName => _$this._salonName;
  set salonName(String? salonName) => _$this._salonName = salonName;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  DateTime? _endsAt;
  DateTime? get endsAt => _$this._endsAt;
  set endsAt(DateTime? endsAt) => _$this._endsAt = endsAt;

  int? _totalDurationMinutes;
  int? get totalDurationMinutes => _$this._totalDurationMinutes;
  set totalDurationMinutes(int? totalDurationMinutes) =>
      _$this._totalDurationMinutes = totalDurationMinutes;

  num? _totalPrice;
  num? get totalPrice => _$this._totalPrice;
  set totalPrice(num? totalPrice) => _$this._totalPrice = totalPrice;

  num? _totalPriceMax;
  num? get totalPriceMax => _$this._totalPriceMax;
  set totalPriceMax(num? totalPriceMax) =>
      _$this._totalPriceMax = totalPriceMax;

  String? _clientComment;
  String? get clientComment => _$this._clientComment;
  set clientComment(String? clientComment) =>
      _$this._clientComment = clientComment;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  ListBuilder<AppointmentItemResponse>? _items;
  ListBuilder<AppointmentItemResponse> get items =>
      _$this._items ??= ListBuilder<AppointmentItemResponse>();
  set items(ListBuilder<AppointmentItemResponse>? items) =>
      _$this._items = items;

  String? _providerComment;
  String? get providerComment => _$this._providerComment;
  set providerComment(String? providerComment) =>
      _$this._providerComment = providerComment;

  String? _clientCancellationNote;
  String? get clientCancellationNote => _$this._clientCancellationNote;
  set clientCancellationNote(String? clientCancellationNote) =>
      _$this._clientCancellationNote = clientCancellationNote;

  String? _cityLabel;
  String? get cityLabel => _$this._cityLabel;
  set cityLabel(String? cityLabel) => _$this._cityLabel = cityLabel;

  String? _districtLabel;
  String? get districtLabel => _$this._districtLabel;
  set districtLabel(String? districtLabel) =>
      _$this._districtLabel = districtLabel;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  AppointmentDetailResponseBuilder() {
    AppointmentDetailResponse._defaults(this);
  }

  AppointmentDetailResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _status = $v.status;
      _masterId = $v.masterId;
      _masterFirstName = $v.masterFirstName;
      _masterLastName = $v.masterLastName;
      _masterProfessionalTitle = $v.masterProfessionalTitle;
      _masterAvatarUrl = $v.masterAvatarUrl;
      _masterType = $v.masterType;
      _salonName = $v.salonName;
      _startsAt = $v.startsAt;
      _endsAt = $v.endsAt;
      _totalDurationMinutes = $v.totalDurationMinutes;
      _totalPrice = $v.totalPrice;
      _totalPriceMax = $v.totalPriceMax;
      _clientComment = $v.clientComment;
      _createdAt = $v.createdAt;
      _items = $v.items?.toBuilder();
      _providerComment = $v.providerComment;
      _clientCancellationNote = $v.clientCancellationNote;
      _cityLabel = $v.cityLabel;
      _districtLabel = $v.districtLabel;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppointmentDetailResponse other) {
    _$v = other as _$AppointmentDetailResponse;
  }

  @override
  void update(void Function(AppointmentDetailResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppointmentDetailResponse build() => _build();

  _$AppointmentDetailResponse _build() {
    _$AppointmentDetailResponse _$result;
    try {
      _$result = _$v ??
          _$AppointmentDetailResponse._(
            id: id,
            status: status,
            masterId: masterId,
            masterFirstName: masterFirstName,
            masterLastName: masterLastName,
            masterProfessionalTitle: masterProfessionalTitle,
            masterAvatarUrl: masterAvatarUrl,
            masterType: masterType,
            salonName: salonName,
            startsAt: startsAt,
            endsAt: endsAt,
            totalDurationMinutes: totalDurationMinutes,
            totalPrice: totalPrice,
            totalPriceMax: totalPriceMax,
            clientComment: clientComment,
            createdAt: createdAt,
            items: _items?.build(),
            providerComment: providerComment,
            clientCancellationNote: clientCancellationNote,
            cityLabel: cityLabel,
            districtLabel: districtLabel,
            street: street,
            buildingNo: buildingNo,
            locationNote: locationNote,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        _items?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AppointmentDetailResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
