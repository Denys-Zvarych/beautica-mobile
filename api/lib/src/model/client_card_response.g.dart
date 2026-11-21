// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_card_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ClientCardResponseKindEnum _$clientCardResponseKindEnum_REGISTERED =
    const ClientCardResponseKindEnum._('REGISTERED');
const ClientCardResponseKindEnum _$clientCardResponseKindEnum_GUEST =
    const ClientCardResponseKindEnum._('GUEST');
const ClientCardResponseKindEnum
    _$clientCardResponseKindEnum_unknownDefaultOpenApi =
    const ClientCardResponseKindEnum._('unknownDefaultOpenApi');

ClientCardResponseKindEnum _$clientCardResponseKindEnumValueOf(String name) {
  switch (name) {
    case 'REGISTERED':
      return _$clientCardResponseKindEnum_REGISTERED;
    case 'GUEST':
      return _$clientCardResponseKindEnum_GUEST;
    case 'unknownDefaultOpenApi':
      return _$clientCardResponseKindEnum_unknownDefaultOpenApi;
    default:
      return _$clientCardResponseKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ClientCardResponseKindEnum> _$clientCardResponseKindEnumValues =
    BuiltSet<ClientCardResponseKindEnum>(const <ClientCardResponseKindEnum>[
  _$clientCardResponseKindEnum_REGISTERED,
  _$clientCardResponseKindEnum_GUEST,
  _$clientCardResponseKindEnum_unknownDefaultOpenApi,
]);

Serializer<ClientCardResponseKindEnum> _$clientCardResponseKindEnumSerializer =
    _$ClientCardResponseKindEnumSerializer();

class _$ClientCardResponseKindEnumSerializer
    implements PrimitiveSerializer<ClientCardResponseKindEnum> {
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
  final Iterable<Type> types = const <Type>[ClientCardResponseKindEnum];
  @override
  final String wireName = 'ClientCardResponseKindEnum';

  @override
  Object serialize(Serializers serializers, ClientCardResponseKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ClientCardResponseKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ClientCardResponseKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ClientCardResponse extends ClientCardResponse {
  @override
  final ClientCardResponseKindEnum? kind;
  @override
  final String? userId;
  @override
  final String? guestBookingId;
  @override
  final String? displayName;
  @override
  final String? avatarUrl;
  @override
  final String? phone;
  @override
  final bool? blocked;
  @override
  final num? ratingAvg;
  @override
  final int? ratingCount;
  @override
  final BuiltList<RatingBucket>? ratingDistribution;
  @override
  final DateTime? firstVisitAt;
  @override
  final DateTime? lastVisitAt;
  @override
  final DateTime? nextVisitAt;
  @override
  final Stats? stats;

  factory _$ClientCardResponse(
          [void Function(ClientCardResponseBuilder)? updates]) =>
      (ClientCardResponseBuilder()..update(updates))._build();

  _$ClientCardResponse._(
      {this.kind,
      this.userId,
      this.guestBookingId,
      this.displayName,
      this.avatarUrl,
      this.phone,
      this.blocked,
      this.ratingAvg,
      this.ratingCount,
      this.ratingDistribution,
      this.firstVisitAt,
      this.lastVisitAt,
      this.nextVisitAt,
      this.stats})
      : super._();
  @override
  ClientCardResponse rebuild(
          void Function(ClientCardResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientCardResponseBuilder toBuilder() =>
      ClientCardResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientCardResponse &&
        kind == other.kind &&
        userId == other.userId &&
        guestBookingId == other.guestBookingId &&
        displayName == other.displayName &&
        avatarUrl == other.avatarUrl &&
        phone == other.phone &&
        blocked == other.blocked &&
        ratingAvg == other.ratingAvg &&
        ratingCount == other.ratingCount &&
        ratingDistribution == other.ratingDistribution &&
        firstVisitAt == other.firstVisitAt &&
        lastVisitAt == other.lastVisitAt &&
        nextVisitAt == other.nextVisitAt &&
        stats == other.stats;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jc(_$hash, guestBookingId.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, blocked.hashCode);
    _$hash = $jc(_$hash, ratingAvg.hashCode);
    _$hash = $jc(_$hash, ratingCount.hashCode);
    _$hash = $jc(_$hash, ratingDistribution.hashCode);
    _$hash = $jc(_$hash, firstVisitAt.hashCode);
    _$hash = $jc(_$hash, lastVisitAt.hashCode);
    _$hash = $jc(_$hash, nextVisitAt.hashCode);
    _$hash = $jc(_$hash, stats.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientCardResponse')
          ..add('kind', kind)
          ..add('userId', userId)
          ..add('guestBookingId', guestBookingId)
          ..add('displayName', displayName)
          ..add('avatarUrl', avatarUrl)
          ..add('phone', phone)
          ..add('blocked', blocked)
          ..add('ratingAvg', ratingAvg)
          ..add('ratingCount', ratingCount)
          ..add('ratingDistribution', ratingDistribution)
          ..add('firstVisitAt', firstVisitAt)
          ..add('lastVisitAt', lastVisitAt)
          ..add('nextVisitAt', nextVisitAt)
          ..add('stats', stats))
        .toString();
  }
}

class ClientCardResponseBuilder
    implements Builder<ClientCardResponse, ClientCardResponseBuilder> {
  _$ClientCardResponse? _$v;

  ClientCardResponseKindEnum? _kind;
  ClientCardResponseKindEnum? get kind => _$this._kind;
  set kind(ClientCardResponseKindEnum? kind) => _$this._kind = kind;

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

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  bool? _blocked;
  bool? get blocked => _$this._blocked;
  set blocked(bool? blocked) => _$this._blocked = blocked;

  num? _ratingAvg;
  num? get ratingAvg => _$this._ratingAvg;
  set ratingAvg(num? ratingAvg) => _$this._ratingAvg = ratingAvg;

  int? _ratingCount;
  int? get ratingCount => _$this._ratingCount;
  set ratingCount(int? ratingCount) => _$this._ratingCount = ratingCount;

  ListBuilder<RatingBucket>? _ratingDistribution;
  ListBuilder<RatingBucket> get ratingDistribution =>
      _$this._ratingDistribution ??= ListBuilder<RatingBucket>();
  set ratingDistribution(ListBuilder<RatingBucket>? ratingDistribution) =>
      _$this._ratingDistribution = ratingDistribution;

  DateTime? _firstVisitAt;
  DateTime? get firstVisitAt => _$this._firstVisitAt;
  set firstVisitAt(DateTime? firstVisitAt) =>
      _$this._firstVisitAt = firstVisitAt;

  DateTime? _lastVisitAt;
  DateTime? get lastVisitAt => _$this._lastVisitAt;
  set lastVisitAt(DateTime? lastVisitAt) => _$this._lastVisitAt = lastVisitAt;

  DateTime? _nextVisitAt;
  DateTime? get nextVisitAt => _$this._nextVisitAt;
  set nextVisitAt(DateTime? nextVisitAt) => _$this._nextVisitAt = nextVisitAt;

  StatsBuilder? _stats;
  StatsBuilder get stats => _$this._stats ??= StatsBuilder();
  set stats(StatsBuilder? stats) => _$this._stats = stats;

  ClientCardResponseBuilder() {
    ClientCardResponse._defaults(this);
  }

  ClientCardResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _userId = $v.userId;
      _guestBookingId = $v.guestBookingId;
      _displayName = $v.displayName;
      _avatarUrl = $v.avatarUrl;
      _phone = $v.phone;
      _blocked = $v.blocked;
      _ratingAvg = $v.ratingAvg;
      _ratingCount = $v.ratingCount;
      _ratingDistribution = $v.ratingDistribution?.toBuilder();
      _firstVisitAt = $v.firstVisitAt;
      _lastVisitAt = $v.lastVisitAt;
      _nextVisitAt = $v.nextVisitAt;
      _stats = $v.stats?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientCardResponse other) {
    _$v = other as _$ClientCardResponse;
  }

  @override
  void update(void Function(ClientCardResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientCardResponse build() => _build();

  _$ClientCardResponse _build() {
    _$ClientCardResponse _$result;
    try {
      _$result = _$v ??
          _$ClientCardResponse._(
            kind: kind,
            userId: userId,
            guestBookingId: guestBookingId,
            displayName: displayName,
            avatarUrl: avatarUrl,
            phone: phone,
            blocked: blocked,
            ratingAvg: ratingAvg,
            ratingCount: ratingCount,
            ratingDistribution: _ratingDistribution?.build(),
            firstVisitAt: firstVisitAt,
            lastVisitAt: lastVisitAt,
            nextVisitAt: nextVisitAt,
            stats: _stats?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'ratingDistribution';
        _ratingDistribution?.build();

        _$failedField = 'stats';
        _stats?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ClientCardResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
