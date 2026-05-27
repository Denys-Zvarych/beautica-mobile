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

Serializer<BookingDetailResponseStatusEnum>
    _$bookingDetailResponseStatusEnumSerializer =
    _$BookingDetailResponseStatusEnumSerializer();

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
      this.providerComment})
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
        providerComment == other.providerComment;
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
          ..add('providerComment', providerComment))
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
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
