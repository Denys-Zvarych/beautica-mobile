// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_detail_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BookingDetailResponseStatusEnum
    _$bookingDetailResponseStatusEnum_PENDING =
    const BookingDetailResponseStatusEnum._('PENDING');
const BookingDetailResponseStatusEnum
    _$bookingDetailResponseStatusEnum_CONFIRMED =
    const BookingDetailResponseStatusEnum._('CONFIRMED');
const BookingDetailResponseStatusEnum
    _$bookingDetailResponseStatusEnum_DECLINED =
    const BookingDetailResponseStatusEnum._('DECLINED');
const BookingDetailResponseStatusEnum
    _$bookingDetailResponseStatusEnum_COMPLETED =
    const BookingDetailResponseStatusEnum._('COMPLETED');
const BookingDetailResponseStatusEnum
    _$bookingDetailResponseStatusEnum_NOT_COMPLETED =
    const BookingDetailResponseStatusEnum._('NOT_COMPLETED');
const BookingDetailResponseStatusEnum
    _$bookingDetailResponseStatusEnum_CANCELLED =
    const BookingDetailResponseStatusEnum._('CANCELLED');

BookingDetailResponseStatusEnum _$bookingDetailResponseStatusEnumValueOf(
    String name) {
  switch (name) {
    case 'PENDING':
      return _$bookingDetailResponseStatusEnum_PENDING;
    case 'CONFIRMED':
      return _$bookingDetailResponseStatusEnum_CONFIRMED;
    case 'DECLINED':
      return _$bookingDetailResponseStatusEnum_DECLINED;
    case 'COMPLETED':
      return _$bookingDetailResponseStatusEnum_COMPLETED;
    case 'NOT_COMPLETED':
      return _$bookingDetailResponseStatusEnum_NOT_COMPLETED;
    case 'CANCELLED':
      return _$bookingDetailResponseStatusEnum_CANCELLED;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BookingDetailResponseStatusEnum>
    _$bookingDetailResponseStatusEnumValues = BuiltSet<
        BookingDetailResponseStatusEnum>(const <BookingDetailResponseStatusEnum>[
  _$bookingDetailResponseStatusEnum_PENDING,
  _$bookingDetailResponseStatusEnum_CONFIRMED,
  _$bookingDetailResponseStatusEnum_DECLINED,
  _$bookingDetailResponseStatusEnum_COMPLETED,
  _$bookingDetailResponseStatusEnum_NOT_COMPLETED,
  _$bookingDetailResponseStatusEnum_CANCELLED,
]);

const BookingDetailResponseMasterTypeEnum
    _$bookingDetailResponseMasterTypeEnum_CLIENT =
    const BookingDetailResponseMasterTypeEnum._('CLIENT');
const BookingDetailResponseMasterTypeEnum
    _$bookingDetailResponseMasterTypeEnum_SALON_OWNER =
    const BookingDetailResponseMasterTypeEnum._('SALON_OWNER');
const BookingDetailResponseMasterTypeEnum
    _$bookingDetailResponseMasterTypeEnum_SALON_ADMIN =
    const BookingDetailResponseMasterTypeEnum._('SALON_ADMIN');
const BookingDetailResponseMasterTypeEnum
    _$bookingDetailResponseMasterTypeEnum_SALON_MASTER =
    const BookingDetailResponseMasterTypeEnum._('SALON_MASTER');
const BookingDetailResponseMasterTypeEnum
    _$bookingDetailResponseMasterTypeEnum_INDEPENDENT_MASTER =
    const BookingDetailResponseMasterTypeEnum._('INDEPENDENT_MASTER');

BookingDetailResponseMasterTypeEnum
    _$bookingDetailResponseMasterTypeEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT':
      return _$bookingDetailResponseMasterTypeEnum_CLIENT;
    case 'SALON_OWNER':
      return _$bookingDetailResponseMasterTypeEnum_SALON_OWNER;
    case 'SALON_ADMIN':
      return _$bookingDetailResponseMasterTypeEnum_SALON_ADMIN;
    case 'SALON_MASTER':
      return _$bookingDetailResponseMasterTypeEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$bookingDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BookingDetailResponseMasterTypeEnum>
    _$bookingDetailResponseMasterTypeEnumValues = BuiltSet<
        BookingDetailResponseMasterTypeEnum>(const <BookingDetailResponseMasterTypeEnum>[
  _$bookingDetailResponseMasterTypeEnum_CLIENT,
  _$bookingDetailResponseMasterTypeEnum_SALON_OWNER,
  _$bookingDetailResponseMasterTypeEnum_SALON_ADMIN,
  _$bookingDetailResponseMasterTypeEnum_SALON_MASTER,
  _$bookingDetailResponseMasterTypeEnum_INDEPENDENT_MASTER,
]);

Serializer<BookingDetailResponseStatusEnum>
    _$bookingDetailResponseStatusEnumSerializer =
    _$BookingDetailResponseStatusEnumSerializer();
Serializer<BookingDetailResponseMasterTypeEnum>
    _$bookingDetailResponseMasterTypeEnumSerializer =
    _$BookingDetailResponseMasterTypeEnumSerializer();

class _$BookingDetailResponseStatusEnumSerializer
    implements PrimitiveSerializer<BookingDetailResponseStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'PENDING': 'PENDING',
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'PENDING': 'PENDING',
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
  };

  @override
  final Iterable<Type> types = const <Type>[BookingDetailResponseStatusEnum];
  @override
  final String wireName = 'BookingDetailResponseStatusEnum';

  @override
  Object serialize(
          Serializers serializers, BookingDetailResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BookingDetailResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BookingDetailResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BookingDetailResponseMasterTypeEnumSerializer
    implements PrimitiveSerializer<BookingDetailResponseMasterTypeEnum> {
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
    BookingDetailResponseMasterTypeEnum
  ];
  @override
  final String wireName = 'BookingDetailResponseMasterTypeEnum';

  @override
  Object serialize(
          Serializers serializers, BookingDetailResponseMasterTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BookingDetailResponseMasterTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BookingDetailResponseMasterTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BookingDetailResponse extends BookingDetailResponse {
  @override
  final String? id;
  @override
  final String? clientId;
  @override
  final String? masterId;
  @override
  final String? masterServiceId;
  @override
  final String? serviceName;
  @override
  final BookingDetailResponseStatusEnum? status;
  @override
  final DateTime? startsAt;
  @override
  final DateTime? endsAt;
  @override
  final num? priceAtBooking;
  @override
  final int? durationMinutesAtBooking;
  @override
  final DateTime? createdAt;
  @override
  final String? clientFirstName;
  @override
  final String? clientLastName;
  @override
  final String? masterFirstName;
  @override
  final String? masterLastName;
  @override
  final String? clientComment;
  @override
  final String? providerComment;
  @override
  final String? masterAvatarUrl;
  @override
  final BookingDetailResponseMasterTypeEnum? masterType;
  @override
  final String? salonName;
  @override
  final String? cityLabel;
  @override
  final String? districtLabel;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? categoryName;
  @override
  final bool? canReview;

  factory _$BookingDetailResponse(
          [void Function(BookingDetailResponseBuilder)? updates]) =>
      (BookingDetailResponseBuilder()..update(updates))._build();

  _$BookingDetailResponse._(
      {this.id,
      this.clientId,
      this.masterId,
      this.masterServiceId,
      this.serviceName,
      this.status,
      this.startsAt,
      this.endsAt,
      this.priceAtBooking,
      this.durationMinutesAtBooking,
      this.createdAt,
      this.clientFirstName,
      this.clientLastName,
      this.masterFirstName,
      this.masterLastName,
      this.clientComment,
      this.providerComment,
      this.masterAvatarUrl,
      this.masterType,
      this.salonName,
      this.cityLabel,
      this.districtLabel,
      this.street,
      this.buildingNo,
      this.categoryName,
      this.canReview})
      : super._();
  @override
  BookingDetailResponse rebuild(
          void Function(BookingDetailResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookingDetailResponseBuilder toBuilder() =>
      BookingDetailResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookingDetailResponse &&
        id == other.id &&
        clientId == other.clientId &&
        masterId == other.masterId &&
        masterServiceId == other.masterServiceId &&
        serviceName == other.serviceName &&
        status == other.status &&
        startsAt == other.startsAt &&
        endsAt == other.endsAt &&
        priceAtBooking == other.priceAtBooking &&
        durationMinutesAtBooking == other.durationMinutesAtBooking &&
        createdAt == other.createdAt &&
        clientFirstName == other.clientFirstName &&
        clientLastName == other.clientLastName &&
        masterFirstName == other.masterFirstName &&
        masterLastName == other.masterLastName &&
        clientComment == other.clientComment &&
        providerComment == other.providerComment &&
        masterAvatarUrl == other.masterAvatarUrl &&
        masterType == other.masterType &&
        salonName == other.salonName &&
        cityLabel == other.cityLabel &&
        districtLabel == other.districtLabel &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        categoryName == other.categoryName &&
        canReview == other.canReview;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, clientId.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterServiceId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, endsAt.hashCode);
    _$hash = $jc(_$hash, priceAtBooking.hashCode);
    _$hash = $jc(_$hash, durationMinutesAtBooking.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, clientFirstName.hashCode);
    _$hash = $jc(_$hash, clientLastName.hashCode);
    _$hash = $jc(_$hash, masterFirstName.hashCode);
    _$hash = $jc(_$hash, masterLastName.hashCode);
    _$hash = $jc(_$hash, clientComment.hashCode);
    _$hash = $jc(_$hash, providerComment.hashCode);
    _$hash = $jc(_$hash, masterAvatarUrl.hashCode);
    _$hash = $jc(_$hash, masterType.hashCode);
    _$hash = $jc(_$hash, salonName.hashCode);
    _$hash = $jc(_$hash, cityLabel.hashCode);
    _$hash = $jc(_$hash, districtLabel.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, categoryName.hashCode);
    _$hash = $jc(_$hash, canReview.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingDetailResponse')
          ..add('id', id)
          ..add('clientId', clientId)
          ..add('masterId', masterId)
          ..add('masterServiceId', masterServiceId)
          ..add('serviceName', serviceName)
          ..add('status', status)
          ..add('startsAt', startsAt)
          ..add('endsAt', endsAt)
          ..add('priceAtBooking', priceAtBooking)
          ..add('durationMinutesAtBooking', durationMinutesAtBooking)
          ..add('createdAt', createdAt)
          ..add('clientFirstName', clientFirstName)
          ..add('clientLastName', clientLastName)
          ..add('masterFirstName', masterFirstName)
          ..add('masterLastName', masterLastName)
          ..add('clientComment', clientComment)
          ..add('providerComment', providerComment)
          ..add('masterAvatarUrl', masterAvatarUrl)
          ..add('masterType', masterType)
          ..add('salonName', salonName)
          ..add('cityLabel', cityLabel)
          ..add('districtLabel', districtLabel)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('categoryName', categoryName)
          ..add('canReview', canReview))
        .toString();
  }
}

class BookingDetailResponseBuilder
    implements Builder<BookingDetailResponse, BookingDetailResponseBuilder> {
  _$BookingDetailResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _clientId;
  String? get clientId => _$this._clientId;
  set clientId(String? clientId) => _$this._clientId = clientId;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterServiceId;
  String? get masterServiceId => _$this._masterServiceId;
  set masterServiceId(String? masterServiceId) =>
      _$this._masterServiceId = masterServiceId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  BookingDetailResponseStatusEnum? _status;
  BookingDetailResponseStatusEnum? get status => _$this._status;
  set status(BookingDetailResponseStatusEnum? status) =>
      _$this._status = status;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  DateTime? _endsAt;
  DateTime? get endsAt => _$this._endsAt;
  set endsAt(DateTime? endsAt) => _$this._endsAt = endsAt;

  num? _priceAtBooking;
  num? get priceAtBooking => _$this._priceAtBooking;
  set priceAtBooking(num? priceAtBooking) =>
      _$this._priceAtBooking = priceAtBooking;

  int? _durationMinutesAtBooking;
  int? get durationMinutesAtBooking => _$this._durationMinutesAtBooking;
  set durationMinutesAtBooking(int? durationMinutesAtBooking) =>
      _$this._durationMinutesAtBooking = durationMinutesAtBooking;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _clientFirstName;
  String? get clientFirstName => _$this._clientFirstName;
  set clientFirstName(String? clientFirstName) =>
      _$this._clientFirstName = clientFirstName;

  String? _clientLastName;
  String? get clientLastName => _$this._clientLastName;
  set clientLastName(String? clientLastName) =>
      _$this._clientLastName = clientLastName;

  String? _masterFirstName;
  String? get masterFirstName => _$this._masterFirstName;
  set masterFirstName(String? masterFirstName) =>
      _$this._masterFirstName = masterFirstName;

  String? _masterLastName;
  String? get masterLastName => _$this._masterLastName;
  set masterLastName(String? masterLastName) =>
      _$this._masterLastName = masterLastName;

  String? _clientComment;
  String? get clientComment => _$this._clientComment;
  set clientComment(String? clientComment) =>
      _$this._clientComment = clientComment;

  String? _providerComment;
  String? get providerComment => _$this._providerComment;
  set providerComment(String? providerComment) =>
      _$this._providerComment = providerComment;

  String? _masterAvatarUrl;
  String? get masterAvatarUrl => _$this._masterAvatarUrl;
  set masterAvatarUrl(String? masterAvatarUrl) =>
      _$this._masterAvatarUrl = masterAvatarUrl;

  BookingDetailResponseMasterTypeEnum? _masterType;
  BookingDetailResponseMasterTypeEnum? get masterType => _$this._masterType;
  set masterType(BookingDetailResponseMasterTypeEnum? masterType) =>
      _$this._masterType = masterType;

  String? _salonName;
  String? get salonName => _$this._salonName;
  set salonName(String? salonName) => _$this._salonName = salonName;

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

  String? _categoryName;
  String? get categoryName => _$this._categoryName;
  set categoryName(String? categoryName) => _$this._categoryName = categoryName;

  bool? _canReview;
  bool? get canReview => _$this._canReview;
  set canReview(bool? canReview) => _$this._canReview = canReview;

  BookingDetailResponseBuilder() {
    BookingDetailResponse._defaults(this);
  }

  BookingDetailResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _clientId = $v.clientId;
      _masterId = $v.masterId;
      _masterServiceId = $v.masterServiceId;
      _serviceName = $v.serviceName;
      _status = $v.status;
      _startsAt = $v.startsAt;
      _endsAt = $v.endsAt;
      _priceAtBooking = $v.priceAtBooking;
      _durationMinutesAtBooking = $v.durationMinutesAtBooking;
      _createdAt = $v.createdAt;
      _clientFirstName = $v.clientFirstName;
      _clientLastName = $v.clientLastName;
      _masterFirstName = $v.masterFirstName;
      _masterLastName = $v.masterLastName;
      _clientComment = $v.clientComment;
      _providerComment = $v.providerComment;
      _masterAvatarUrl = $v.masterAvatarUrl;
      _masterType = $v.masterType;
      _salonName = $v.salonName;
      _cityLabel = $v.cityLabel;
      _districtLabel = $v.districtLabel;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _categoryName = $v.categoryName;
      _canReview = $v.canReview;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookingDetailResponse other) {
    _$v = other as _$BookingDetailResponse;
  }

  @override
  void update(void Function(BookingDetailResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookingDetailResponse build() => _build();

  _$BookingDetailResponse _build() {
    final _$result = _$v ??
        _$BookingDetailResponse._(
          id: id,
          clientId: clientId,
          masterId: masterId,
          masterServiceId: masterServiceId,
          serviceName: serviceName,
          status: status,
          startsAt: startsAt,
          endsAt: endsAt,
          priceAtBooking: priceAtBooking,
          durationMinutesAtBooking: durationMinutesAtBooking,
          createdAt: createdAt,
          clientFirstName: clientFirstName,
          clientLastName: clientLastName,
          masterFirstName: masterFirstName,
          masterLastName: masterLastName,
          clientComment: clientComment,
          providerComment: providerComment,
          masterAvatarUrl: masterAvatarUrl,
          masterType: masterType,
          salonName: salonName,
          cityLabel: cityLabel,
          districtLabel: districtLabel,
          street: street,
          buildingNo: buildingNo,
          categoryName: categoryName,
          canReview: canReview,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
