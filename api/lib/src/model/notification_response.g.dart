// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_BOOKING_CREATED =
    const NotificationResponseTypeEnum._('BOOKING_CREATED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_BOOKING_CANCELLED_BY_CLIENT =
    const NotificationResponseTypeEnum._('BOOKING_CANCELLED_BY_CLIENT');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_BOOKING_DECLINED =
    const NotificationResponseTypeEnum._('BOOKING_DECLINED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_BOOKING_NOT_COMPLETED =
    const NotificationResponseTypeEnum._('BOOKING_NOT_COMPLETED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_BOOKING_RESCHEDULED =
    const NotificationResponseTypeEnum._('BOOKING_RESCHEDULED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_REVIEW_REQUESTED =
    const NotificationResponseTypeEnum._('REVIEW_REQUESTED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_BOOKING_CANCELLED_SALON_CLOSED =
    const NotificationResponseTypeEnum._('BOOKING_CANCELLED_SALON_CLOSED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_BOOKING_CANCELLED_MASTER_REMOVED =
    const NotificationResponseTypeEnum._('BOOKING_CANCELLED_MASTER_REMOVED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_REVIEW_RECEIVED =
    const NotificationResponseTypeEnum._('REVIEW_RECEIVED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_INVITE_ACCEPTED =
    const NotificationResponseTypeEnum._('INVITE_ACCEPTED');
const NotificationResponseTypeEnum
    _$notificationResponseTypeEnum_unknownDefaultOpenApi =
    const NotificationResponseTypeEnum._('unknownDefaultOpenApi');

NotificationResponseTypeEnum _$notificationResponseTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'BOOKING_CREATED':
      return _$notificationResponseTypeEnum_BOOKING_CREATED;
    case 'BOOKING_CANCELLED_BY_CLIENT':
      return _$notificationResponseTypeEnum_BOOKING_CANCELLED_BY_CLIENT;
    case 'BOOKING_DECLINED':
      return _$notificationResponseTypeEnum_BOOKING_DECLINED;
    case 'BOOKING_NOT_COMPLETED':
      return _$notificationResponseTypeEnum_BOOKING_NOT_COMPLETED;
    case 'BOOKING_RESCHEDULED':
      return _$notificationResponseTypeEnum_BOOKING_RESCHEDULED;
    case 'REVIEW_REQUESTED':
      return _$notificationResponseTypeEnum_REVIEW_REQUESTED;
    case 'BOOKING_CANCELLED_SALON_CLOSED':
      return _$notificationResponseTypeEnum_BOOKING_CANCELLED_SALON_CLOSED;
    case 'BOOKING_CANCELLED_MASTER_REMOVED':
      return _$notificationResponseTypeEnum_BOOKING_CANCELLED_MASTER_REMOVED;
    case 'REVIEW_RECEIVED':
      return _$notificationResponseTypeEnum_REVIEW_RECEIVED;
    case 'INVITE_ACCEPTED':
      return _$notificationResponseTypeEnum_INVITE_ACCEPTED;
    case 'unknownDefaultOpenApi':
      return _$notificationResponseTypeEnum_unknownDefaultOpenApi;
    default:
      return _$notificationResponseTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<NotificationResponseTypeEnum>
    _$notificationResponseTypeEnumValues =
    BuiltSet<NotificationResponseTypeEnum>(const <NotificationResponseTypeEnum>[
  _$notificationResponseTypeEnum_BOOKING_CREATED,
  _$notificationResponseTypeEnum_BOOKING_CANCELLED_BY_CLIENT,
  _$notificationResponseTypeEnum_BOOKING_DECLINED,
  _$notificationResponseTypeEnum_BOOKING_NOT_COMPLETED,
  _$notificationResponseTypeEnum_BOOKING_RESCHEDULED,
  _$notificationResponseTypeEnum_REVIEW_REQUESTED,
  _$notificationResponseTypeEnum_BOOKING_CANCELLED_SALON_CLOSED,
  _$notificationResponseTypeEnum_BOOKING_CANCELLED_MASTER_REMOVED,
  _$notificationResponseTypeEnum_REVIEW_RECEIVED,
  _$notificationResponseTypeEnum_INVITE_ACCEPTED,
  _$notificationResponseTypeEnum_unknownDefaultOpenApi,
]);

Serializer<NotificationResponseTypeEnum>
    _$notificationResponseTypeEnumSerializer =
    _$NotificationResponseTypeEnumSerializer();

class _$NotificationResponseTypeEnumSerializer
    implements PrimitiveSerializer<NotificationResponseTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'BOOKING_CREATED': 'BOOKING_CREATED',
    'BOOKING_CANCELLED_BY_CLIENT': 'BOOKING_CANCELLED_BY_CLIENT',
    'BOOKING_DECLINED': 'BOOKING_DECLINED',
    'BOOKING_NOT_COMPLETED': 'BOOKING_NOT_COMPLETED',
    'BOOKING_RESCHEDULED': 'BOOKING_RESCHEDULED',
    'REVIEW_REQUESTED': 'REVIEW_REQUESTED',
    'BOOKING_CANCELLED_SALON_CLOSED': 'BOOKING_CANCELLED_SALON_CLOSED',
    'BOOKING_CANCELLED_MASTER_REMOVED': 'BOOKING_CANCELLED_MASTER_REMOVED',
    'REVIEW_RECEIVED': 'REVIEW_RECEIVED',
    'INVITE_ACCEPTED': 'INVITE_ACCEPTED',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'BOOKING_CREATED': 'BOOKING_CREATED',
    'BOOKING_CANCELLED_BY_CLIENT': 'BOOKING_CANCELLED_BY_CLIENT',
    'BOOKING_DECLINED': 'BOOKING_DECLINED',
    'BOOKING_NOT_COMPLETED': 'BOOKING_NOT_COMPLETED',
    'BOOKING_RESCHEDULED': 'BOOKING_RESCHEDULED',
    'REVIEW_REQUESTED': 'REVIEW_REQUESTED',
    'BOOKING_CANCELLED_SALON_CLOSED': 'BOOKING_CANCELLED_SALON_CLOSED',
    'BOOKING_CANCELLED_MASTER_REMOVED': 'BOOKING_CANCELLED_MASTER_REMOVED',
    'REVIEW_RECEIVED': 'REVIEW_RECEIVED',
    'INVITE_ACCEPTED': 'INVITE_ACCEPTED',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[NotificationResponseTypeEnum];
  @override
  final String wireName = 'NotificationResponseTypeEnum';

  @override
  Object serialize(Serializers serializers, NotificationResponseTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  NotificationResponseTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      NotificationResponseTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$NotificationResponse extends NotificationResponse {
  @override
  final String? id;
  @override
  final NotificationResponseTypeEnum? type;
  @override
  final DateTime? createdAt;
  @override
  final bool? read;
  @override
  final NotificationTarget? target;
  @override
  final NotificationParams? params;

  factory _$NotificationResponse(
          [void Function(NotificationResponseBuilder)? updates]) =>
      (NotificationResponseBuilder()..update(updates))._build();

  _$NotificationResponse._(
      {this.id, this.type, this.createdAt, this.read, this.target, this.params})
      : super._();
  @override
  NotificationResponse rebuild(
          void Function(NotificationResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NotificationResponseBuilder toBuilder() =>
      NotificationResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationResponse &&
        id == other.id &&
        type == other.type &&
        createdAt == other.createdAt &&
        read == other.read &&
        target == other.target &&
        params == other.params;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, read.hashCode);
    _$hash = $jc(_$hash, target.hashCode);
    _$hash = $jc(_$hash, params.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationResponse')
          ..add('id', id)
          ..add('type', type)
          ..add('createdAt', createdAt)
          ..add('read', read)
          ..add('target', target)
          ..add('params', params))
        .toString();
  }
}

class NotificationResponseBuilder
    implements Builder<NotificationResponse, NotificationResponseBuilder> {
  _$NotificationResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  NotificationResponseTypeEnum? _type;
  NotificationResponseTypeEnum? get type => _$this._type;
  set type(NotificationResponseTypeEnum? type) => _$this._type = type;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  bool? _read;
  bool? get read => _$this._read;
  set read(bool? read) => _$this._read = read;

  NotificationTargetBuilder? _target;
  NotificationTargetBuilder get target =>
      _$this._target ??= NotificationTargetBuilder();
  set target(NotificationTargetBuilder? target) => _$this._target = target;

  NotificationParamsBuilder? _params;
  NotificationParamsBuilder get params =>
      _$this._params ??= NotificationParamsBuilder();
  set params(NotificationParamsBuilder? params) => _$this._params = params;

  NotificationResponseBuilder() {
    NotificationResponse._defaults(this);
  }

  NotificationResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _type = $v.type;
      _createdAt = $v.createdAt;
      _read = $v.read;
      _target = $v.target?.toBuilder();
      _params = $v.params?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationResponse other) {
    _$v = other as _$NotificationResponse;
  }

  @override
  void update(void Function(NotificationResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationResponse build() => _build();

  _$NotificationResponse _build() {
    _$NotificationResponse _$result;
    try {
      _$result = _$v ??
          _$NotificationResponse._(
            id: id,
            type: type,
            createdAt: createdAt,
            read: read,
            target: _target?.build(),
            params: _params?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'target';
        _target?.build();
        _$failedField = 'params';
        _params?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'NotificationResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
