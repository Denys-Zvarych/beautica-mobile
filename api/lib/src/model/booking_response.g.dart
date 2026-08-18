// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BookingResponseStatusEnum _$bookingResponseStatusEnum_CONFIRMED =
    const BookingResponseStatusEnum._('CONFIRMED');
const BookingResponseStatusEnum _$bookingResponseStatusEnum_DECLINED =
    const BookingResponseStatusEnum._('DECLINED');
const BookingResponseStatusEnum _$bookingResponseStatusEnum_COMPLETED =
    const BookingResponseStatusEnum._('COMPLETED');
const BookingResponseStatusEnum _$bookingResponseStatusEnum_NOT_COMPLETED =
    const BookingResponseStatusEnum._('NOT_COMPLETED');
const BookingResponseStatusEnum _$bookingResponseStatusEnum_CANCELLED =
    const BookingResponseStatusEnum._('CANCELLED');

BookingResponseStatusEnum _$bookingResponseStatusEnumValueOf(String name) {
  switch (name) {
    case 'CONFIRMED':
      return _$bookingResponseStatusEnum_CONFIRMED;
    case 'DECLINED':
      return _$bookingResponseStatusEnum_DECLINED;
    case 'COMPLETED':
      return _$bookingResponseStatusEnum_COMPLETED;
    case 'NOT_COMPLETED':
      return _$bookingResponseStatusEnum_NOT_COMPLETED;
    case 'CANCELLED':
      return _$bookingResponseStatusEnum_CANCELLED;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BookingResponseStatusEnum> _$bookingResponseStatusEnumValues =
    BuiltSet<BookingResponseStatusEnum>(const <BookingResponseStatusEnum>[
  _$bookingResponseStatusEnum_CONFIRMED,
  _$bookingResponseStatusEnum_DECLINED,
  _$bookingResponseStatusEnum_COMPLETED,
  _$bookingResponseStatusEnum_NOT_COMPLETED,
  _$bookingResponseStatusEnum_CANCELLED,
]);

Serializer<BookingResponseStatusEnum> _$bookingResponseStatusEnumSerializer =
    _$BookingResponseStatusEnumSerializer();

class _$BookingResponseStatusEnumSerializer
    implements PrimitiveSerializer<BookingResponseStatusEnum> {
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
  final Iterable<Type> types = const <Type>[BookingResponseStatusEnum];
  @override
  final String wireName = 'BookingResponseStatusEnum';

  @override
  Object serialize(Serializers serializers, BookingResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BookingResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BookingResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BookingResponse extends BookingResponse {
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
  final BookingResponseStatusEnum? status;
  @override
  final DateTime? startsAt;
  @override
  final DateTime? endsAt;
  @override
  final num? priceAtBooking;
  @override
  final num? priceMaxAtBooking;
  @override
  final int? durationMinutesAtBooking;
  @override
  final DateTime? createdAt;
  @override
  final String? appointmentId;
  @override
  final bool? awaitingClosure;

  factory _$BookingResponse([void Function(BookingResponseBuilder)? updates]) =>
      (BookingResponseBuilder()..update(updates))._build();

  _$BookingResponse._(
      {this.id,
      this.clientId,
      this.masterId,
      this.masterServiceId,
      this.serviceName,
      this.status,
      this.startsAt,
      this.endsAt,
      this.priceAtBooking,
      this.priceMaxAtBooking,
      this.durationMinutesAtBooking,
      this.createdAt,
      this.appointmentId,
      this.awaitingClosure})
      : super._();
  @override
  BookingResponse rebuild(void Function(BookingResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookingResponseBuilder toBuilder() => BookingResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookingResponse &&
        id == other.id &&
        clientId == other.clientId &&
        masterId == other.masterId &&
        masterServiceId == other.masterServiceId &&
        serviceName == other.serviceName &&
        status == other.status &&
        startsAt == other.startsAt &&
        endsAt == other.endsAt &&
        priceAtBooking == other.priceAtBooking &&
        priceMaxAtBooking == other.priceMaxAtBooking &&
        durationMinutesAtBooking == other.durationMinutesAtBooking &&
        createdAt == other.createdAt &&
        appointmentId == other.appointmentId &&
        awaitingClosure == other.awaitingClosure;
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
    _$hash = $jc(_$hash, priceMaxAtBooking.hashCode);
    _$hash = $jc(_$hash, durationMinutesAtBooking.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, appointmentId.hashCode);
    _$hash = $jc(_$hash, awaitingClosure.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingResponse')
          ..add('id', id)
          ..add('clientId', clientId)
          ..add('masterId', masterId)
          ..add('masterServiceId', masterServiceId)
          ..add('serviceName', serviceName)
          ..add('status', status)
          ..add('startsAt', startsAt)
          ..add('endsAt', endsAt)
          ..add('priceAtBooking', priceAtBooking)
          ..add('priceMaxAtBooking', priceMaxAtBooking)
          ..add('durationMinutesAtBooking', durationMinutesAtBooking)
          ..add('createdAt', createdAt)
          ..add('appointmentId', appointmentId)
          ..add('awaitingClosure', awaitingClosure))
        .toString();
  }
}

class BookingResponseBuilder
    implements Builder<BookingResponse, BookingResponseBuilder> {
  _$BookingResponse? _$v;

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

  BookingResponseStatusEnum? _status;
  BookingResponseStatusEnum? get status => _$this._status;
  set status(BookingResponseStatusEnum? status) => _$this._status = status;

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

  num? _priceMaxAtBooking;
  num? get priceMaxAtBooking => _$this._priceMaxAtBooking;
  set priceMaxAtBooking(num? priceMaxAtBooking) =>
      _$this._priceMaxAtBooking = priceMaxAtBooking;

  int? _durationMinutesAtBooking;
  int? get durationMinutesAtBooking => _$this._durationMinutesAtBooking;
  set durationMinutesAtBooking(int? durationMinutesAtBooking) =>
      _$this._durationMinutesAtBooking = durationMinutesAtBooking;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _appointmentId;
  String? get appointmentId => _$this._appointmentId;
  set appointmentId(String? appointmentId) =>
      _$this._appointmentId = appointmentId;

  bool? _awaitingClosure;
  bool? get awaitingClosure => _$this._awaitingClosure;
  set awaitingClosure(bool? awaitingClosure) =>
      _$this._awaitingClosure = awaitingClosure;

  BookingResponseBuilder() {
    BookingResponse._defaults(this);
  }

  BookingResponseBuilder get _$this {
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
      _priceMaxAtBooking = $v.priceMaxAtBooking;
      _durationMinutesAtBooking = $v.durationMinutesAtBooking;
      _createdAt = $v.createdAt;
      _appointmentId = $v.appointmentId;
      _awaitingClosure = $v.awaitingClosure;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookingResponse other) {
    _$v = other as _$BookingResponse;
  }

  @override
  void update(void Function(BookingResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookingResponse build() => _build();

  _$BookingResponse _build() {
    final _$result = _$v ??
        _$BookingResponse._(
          id: id,
          clientId: clientId,
          masterId: masterId,
          masterServiceId: masterServiceId,
          serviceName: serviceName,
          status: status,
          startsAt: startsAt,
          endsAt: endsAt,
          priceAtBooking: priceAtBooking,
          priceMaxAtBooking: priceMaxAtBooking,
          durationMinutesAtBooking: durationMinutesAtBooking,
          createdAt: createdAt,
          appointmentId: appointmentId,
          awaitingClosure: awaitingClosure,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
