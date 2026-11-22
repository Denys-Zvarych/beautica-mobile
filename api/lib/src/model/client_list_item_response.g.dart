// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_list_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ClientListItemResponseKindEnum
    _$clientListItemResponseKindEnum_REGISTERED =
    const ClientListItemResponseKindEnum._('REGISTERED');
const ClientListItemResponseKindEnum _$clientListItemResponseKindEnum_GUEST =
    const ClientListItemResponseKindEnum._('GUEST');
const ClientListItemResponseKindEnum
    _$clientListItemResponseKindEnum_unknownDefaultOpenApi =
    const ClientListItemResponseKindEnum._('unknownDefaultOpenApi');

ClientListItemResponseKindEnum _$clientListItemResponseKindEnumValueOf(
    String name) {
  switch (name) {
    case 'REGISTERED':
      return _$clientListItemResponseKindEnum_REGISTERED;
    case 'GUEST':
      return _$clientListItemResponseKindEnum_GUEST;
    case 'unknownDefaultOpenApi':
      return _$clientListItemResponseKindEnum_unknownDefaultOpenApi;
    default:
      return _$clientListItemResponseKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ClientListItemResponseKindEnum>
    _$clientListItemResponseKindEnumValues = BuiltSet<
        ClientListItemResponseKindEnum>(const <ClientListItemResponseKindEnum>[
  _$clientListItemResponseKindEnum_REGISTERED,
  _$clientListItemResponseKindEnum_GUEST,
  _$clientListItemResponseKindEnum_unknownDefaultOpenApi,
]);

Serializer<ClientListItemResponseKindEnum>
    _$clientListItemResponseKindEnumSerializer =
    _$ClientListItemResponseKindEnumSerializer();

class _$ClientListItemResponseKindEnumSerializer
    implements PrimitiveSerializer<ClientListItemResponseKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'REGISTERED': 'REGISTERED',
    'GUEST': 'GUEST',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'REGISTERED': 'REGISTERED',
    'GUEST': 'GUEST',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ClientListItemResponseKindEnum];
  @override
  final String wireName = 'ClientListItemResponseKindEnum';

  @override
  Object serialize(
          Serializers serializers, ClientListItemResponseKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ClientListItemResponseKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ClientListItemResponseKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ClientListItemResponse extends ClientListItemResponse {
  @override
  final ClientListItemResponseKindEnum? kind;
  @override
  final String? userId;
  @override
  final String? guestBookingId;
  @override
  final String? displayName;
  @override
  final String? avatarUrl;
  @override
  final DateTime? lastVisitAt;
  @override
  final DateTime? nextVisitAt;
  @override
  final int? completedVisits;
  @override
  final num? ratingAvg;
  @override
  final int? ratingCount;
  @override
  final bool? blocked;

  factory _$ClientListItemResponse(
          [void Function(ClientListItemResponseBuilder)? updates]) =>
      (ClientListItemResponseBuilder()..update(updates))._build();

  _$ClientListItemResponse._(
      {this.kind,
      this.userId,
      this.guestBookingId,
      this.displayName,
      this.avatarUrl,
      this.lastVisitAt,
      this.nextVisitAt,
      this.completedVisits,
      this.ratingAvg,
      this.ratingCount,
      this.blocked})
      : super._();
  @override
  ClientListItemResponse rebuild(
          void Function(ClientListItemResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientListItemResponseBuilder toBuilder() =>
      ClientListItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientListItemResponse &&
        kind == other.kind &&
        userId == other.userId &&
        guestBookingId == other.guestBookingId &&
        displayName == other.displayName &&
        avatarUrl == other.avatarUrl &&
        lastVisitAt == other.lastVisitAt &&
        nextVisitAt == other.nextVisitAt &&
        completedVisits == other.completedVisits &&
        ratingAvg == other.ratingAvg &&
        ratingCount == other.ratingCount &&
        blocked == other.blocked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jc(_$hash, guestBookingId.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, lastVisitAt.hashCode);
    _$hash = $jc(_$hash, nextVisitAt.hashCode);
    _$hash = $jc(_$hash, completedVisits.hashCode);
    _$hash = $jc(_$hash, ratingAvg.hashCode);
    _$hash = $jc(_$hash, ratingCount.hashCode);
    _$hash = $jc(_$hash, blocked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientListItemResponse')
          ..add('kind', kind)
          ..add('userId', userId)
          ..add('guestBookingId', guestBookingId)
          ..add('displayName', displayName)
          ..add('avatarUrl', avatarUrl)
          ..add('lastVisitAt', lastVisitAt)
          ..add('nextVisitAt', nextVisitAt)
          ..add('completedVisits', completedVisits)
          ..add('ratingAvg', ratingAvg)
          ..add('ratingCount', ratingCount)
          ..add('blocked', blocked))
        .toString();
  }
}

class ClientListItemResponseBuilder
    implements Builder<ClientListItemResponse, ClientListItemResponseBuilder> {
  _$ClientListItemResponse? _$v;

  ClientListItemResponseKindEnum? _kind;
  ClientListItemResponseKindEnum? get kind => _$this._kind;
  set kind(ClientListItemResponseKindEnum? kind) => _$this._kind = kind;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  String? _guestBookingId;
  String? get guestBookingId => _$this._guestBookingId;
  set guestBookingId(String? guestBookingId) =>
      _$this._guestBookingId = guestBookingId;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  DateTime? _lastVisitAt;
  DateTime? get lastVisitAt => _$this._lastVisitAt;
  set lastVisitAt(DateTime? lastVisitAt) => _$this._lastVisitAt = lastVisitAt;

  DateTime? _nextVisitAt;
  DateTime? get nextVisitAt => _$this._nextVisitAt;
  set nextVisitAt(DateTime? nextVisitAt) => _$this._nextVisitAt = nextVisitAt;

  int? _completedVisits;
  int? get completedVisits => _$this._completedVisits;
  set completedVisits(int? completedVisits) =>
      _$this._completedVisits = completedVisits;

  num? _ratingAvg;
  num? get ratingAvg => _$this._ratingAvg;
  set ratingAvg(num? ratingAvg) => _$this._ratingAvg = ratingAvg;

  int? _ratingCount;
  int? get ratingCount => _$this._ratingCount;
  set ratingCount(int? ratingCount) => _$this._ratingCount = ratingCount;

  bool? _blocked;
  bool? get blocked => _$this._blocked;
  set blocked(bool? blocked) => _$this._blocked = blocked;

  ClientListItemResponseBuilder() {
    ClientListItemResponse._defaults(this);
  }

  ClientListItemResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _userId = $v.userId;
      _guestBookingId = $v.guestBookingId;
      _displayName = $v.displayName;
      _avatarUrl = $v.avatarUrl;
      _lastVisitAt = $v.lastVisitAt;
      _nextVisitAt = $v.nextVisitAt;
      _completedVisits = $v.completedVisits;
      _ratingAvg = $v.ratingAvg;
      _ratingCount = $v.ratingCount;
      _blocked = $v.blocked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientListItemResponse other) {
    _$v = other as _$ClientListItemResponse;
  }

  @override
  void update(void Function(ClientListItemResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientListItemResponse build() => _build();

  _$ClientListItemResponse _build() {
    final _$result = _$v ??
        _$ClientListItemResponse._(
          kind: kind,
          userId: userId,
          guestBookingId: guestBookingId,
          displayName: displayName,
          avatarUrl: avatarUrl,
          lastVisitAt: lastVisitAt,
          nextVisitAt: nextVisitAt,
          completedVisits: completedVisits,
          ratingAvg: ratingAvg,
          ratingCount: ratingCount,
          blocked: blocked,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
