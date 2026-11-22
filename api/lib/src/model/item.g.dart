// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ItemStatusEnum _$itemStatusEnum_CONFIRMED =
    const ItemStatusEnum._('CONFIRMED');
const ItemStatusEnum _$itemStatusEnum_DECLINED =
    const ItemStatusEnum._('DECLINED');
const ItemStatusEnum _$itemStatusEnum_COMPLETED =
    const ItemStatusEnum._('COMPLETED');
const ItemStatusEnum _$itemStatusEnum_NOT_COMPLETED =
    const ItemStatusEnum._('NOT_COMPLETED');
const ItemStatusEnum _$itemStatusEnum_CANCELLED =
    const ItemStatusEnum._('CANCELLED');
const ItemStatusEnum _$itemStatusEnum_unknownDefaultOpenApi =
    const ItemStatusEnum._('unknownDefaultOpenApi');

ItemStatusEnum _$itemStatusEnumValueOf(String name) {
  switch (name) {
    case 'CONFIRMED':
      return _$itemStatusEnum_CONFIRMED;
    case 'DECLINED':
      return _$itemStatusEnum_DECLINED;
    case 'COMPLETED':
      return _$itemStatusEnum_COMPLETED;
    case 'NOT_COMPLETED':
      return _$itemStatusEnum_NOT_COMPLETED;
    case 'CANCELLED':
      return _$itemStatusEnum_CANCELLED;
    case 'unknownDefaultOpenApi':
      return _$itemStatusEnum_unknownDefaultOpenApi;
    default:
      return _$itemStatusEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ItemStatusEnum> _$itemStatusEnumValues =
    BuiltSet<ItemStatusEnum>(const <ItemStatusEnum>[
  _$itemStatusEnum_CONFIRMED,
  _$itemStatusEnum_DECLINED,
  _$itemStatusEnum_COMPLETED,
  _$itemStatusEnum_NOT_COMPLETED,
  _$itemStatusEnum_CANCELLED,
  _$itemStatusEnum_unknownDefaultOpenApi,
]);

Serializer<ItemStatusEnum> _$itemStatusEnumSerializer =
    _$ItemStatusEnumSerializer();

class _$ItemStatusEnumSerializer
    implements PrimitiveSerializer<ItemStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ItemStatusEnum];
  @override
  final String wireName = 'ItemStatusEnum';

  @override
  Object serialize(Serializers serializers, ItemStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ItemStatusEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ItemStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$Item extends Item {
  @override
  final String? bookingId;
  @override
  final String? serviceName;
  @override
  final ItemStatusEnum? status;
  @override
  final DateTime? startsAt;
  @override
  final String? masterId;
  @override
  final String? masterDisplayName;
  @override
  final num? priceAtBooking;
  @override
  final num? priceMaxAtBooking;

  factory _$Item([void Function(ItemBuilder)? updates]) =>
      (ItemBuilder()..update(updates))._build();

  _$Item._(
      {this.bookingId,
      this.serviceName,
      this.status,
      this.startsAt,
      this.masterId,
      this.masterDisplayName,
      this.priceAtBooking,
      this.priceMaxAtBooking})
      : super._();
  @override
  Item rebuild(void Function(ItemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemBuilder toBuilder() => ItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Item &&
        bookingId == other.bookingId &&
        serviceName == other.serviceName &&
        status == other.status &&
        startsAt == other.startsAt &&
        masterId == other.masterId &&
        masterDisplayName == other.masterDisplayName &&
        priceAtBooking == other.priceAtBooking &&
        priceMaxAtBooking == other.priceMaxAtBooking;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterDisplayName.hashCode);
    _$hash = $jc(_$hash, priceAtBooking.hashCode);
    _$hash = $jc(_$hash, priceMaxAtBooking.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Item')
          ..add('bookingId', bookingId)
          ..add('serviceName', serviceName)
          ..add('status', status)
          ..add('startsAt', startsAt)
          ..add('masterId', masterId)
          ..add('masterDisplayName', masterDisplayName)
          ..add('priceAtBooking', priceAtBooking)
          ..add('priceMaxAtBooking', priceMaxAtBooking))
        .toString();
  }
}

class ItemBuilder implements Builder<Item, ItemBuilder> {
  _$Item? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  ItemStatusEnum? _status;
  ItemStatusEnum? get status => _$this._status;
  set status(ItemStatusEnum? status) => _$this._status = status;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterDisplayName;
  String? get masterDisplayName => _$this._masterDisplayName;
  set masterDisplayName(String? masterDisplayName) =>
      _$this._masterDisplayName = masterDisplayName;

  num? _priceAtBooking;
  num? get priceAtBooking => _$this._priceAtBooking;
  set priceAtBooking(num? priceAtBooking) =>
      _$this._priceAtBooking = priceAtBooking;

  num? _priceMaxAtBooking;
  num? get priceMaxAtBooking => _$this._priceMaxAtBooking;
  set priceMaxAtBooking(num? priceMaxAtBooking) =>
      _$this._priceMaxAtBooking = priceMaxAtBooking;

  ItemBuilder() {
    Item._defaults(this);
  }

  ItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _serviceName = $v.serviceName;
      _status = $v.status;
      _startsAt = $v.startsAt;
      _masterId = $v.masterId;
      _masterDisplayName = $v.masterDisplayName;
      _priceAtBooking = $v.priceAtBooking;
      _priceMaxAtBooking = $v.priceMaxAtBooking;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Item other) {
    _$v = other as _$Item;
  }

  @override
  void update(void Function(ItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Item build() => _build();

  _$Item _build() {
    final _$result = _$v ??
        _$Item._(
          bookingId: bookingId,
          serviceName: serviceName,
          status: status,
          startsAt: startsAt,
          masterId: masterId,
          masterDisplayName: masterDisplayName,
          priceAtBooking: priceAtBooking,
          priceMaxAtBooking: priceMaxAtBooking,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
