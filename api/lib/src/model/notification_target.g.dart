// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_target.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const NotificationTargetKindEnum _$notificationTargetKindEnum_BOOKING =
    const NotificationTargetKindEnum._('BOOKING');
const NotificationTargetKindEnum _$notificationTargetKindEnum_BOOKING_REVIEW =
    const NotificationTargetKindEnum._('BOOKING_REVIEW');
const NotificationTargetKindEnum _$notificationTargetKindEnum_SALON_TEAM =
    const NotificationTargetKindEnum._('SALON_TEAM');
const NotificationTargetKindEnum _$notificationTargetKindEnum_NONE =
    const NotificationTargetKindEnum._('NONE');
const NotificationTargetKindEnum
    _$notificationTargetKindEnum_unknownDefaultOpenApi =
    const NotificationTargetKindEnum._('unknownDefaultOpenApi');

NotificationTargetKindEnum _$notificationTargetKindEnumValueOf(String name) {
  switch (name) {
    case 'BOOKING':
      return _$notificationTargetKindEnum_BOOKING;
    case 'BOOKING_REVIEW':
      return _$notificationTargetKindEnum_BOOKING_REVIEW;
    case 'SALON_TEAM':
      return _$notificationTargetKindEnum_SALON_TEAM;
    case 'NONE':
      return _$notificationTargetKindEnum_NONE;
    case 'unknownDefaultOpenApi':
      return _$notificationTargetKindEnum_unknownDefaultOpenApi;
    default:
      return _$notificationTargetKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<NotificationTargetKindEnum> _$notificationTargetKindEnumValues =
    BuiltSet<NotificationTargetKindEnum>(const <NotificationTargetKindEnum>[
  _$notificationTargetKindEnum_BOOKING,
  _$notificationTargetKindEnum_BOOKING_REVIEW,
  _$notificationTargetKindEnum_SALON_TEAM,
  _$notificationTargetKindEnum_NONE,
  _$notificationTargetKindEnum_unknownDefaultOpenApi,
]);

Serializer<NotificationTargetKindEnum> _$notificationTargetKindEnumSerializer =
    _$NotificationTargetKindEnumSerializer();

class _$NotificationTargetKindEnumSerializer
    implements PrimitiveSerializer<NotificationTargetKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'BOOKING': 'BOOKING',
    'BOOKING_REVIEW': 'BOOKING_REVIEW',
    'SALON_TEAM': 'SALON_TEAM',
    'NONE': 'NONE',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'BOOKING': 'BOOKING',
    'BOOKING_REVIEW': 'BOOKING_REVIEW',
    'SALON_TEAM': 'SALON_TEAM',
    'NONE': 'NONE',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[NotificationTargetKindEnum];
  @override
  final String wireName = 'NotificationTargetKindEnum';

  @override
  Object serialize(Serializers serializers, NotificationTargetKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  NotificationTargetKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      NotificationTargetKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$NotificationTarget extends NotificationTarget {
  @override
  final NotificationTargetKindEnum? kind;
  @override
  final String? bookingId;
  @override
  final String? appointmentId;
  @override
  final String? salonId;

  factory _$NotificationTarget(
          [void Function(NotificationTargetBuilder)? updates]) =>
      (NotificationTargetBuilder()..update(updates))._build();

  _$NotificationTarget._(
      {this.kind, this.bookingId, this.appointmentId, this.salonId})
      : super._();
  @override
  NotificationTarget rebuild(
          void Function(NotificationTargetBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NotificationTargetBuilder toBuilder() =>
      NotificationTargetBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationTarget &&
        kind == other.kind &&
        bookingId == other.bookingId &&
        appointmentId == other.appointmentId &&
        salonId == other.salonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, appointmentId.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationTarget')
          ..add('kind', kind)
          ..add('bookingId', bookingId)
          ..add('appointmentId', appointmentId)
          ..add('salonId', salonId))
        .toString();
  }
}

class NotificationTargetBuilder
    implements Builder<NotificationTarget, NotificationTargetBuilder> {
  _$NotificationTarget? _$v;

  NotificationTargetKindEnum? _kind;
  NotificationTargetKindEnum? get kind => _$this._kind;
  set kind(NotificationTargetKindEnum? kind) => _$this._kind = kind;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _appointmentId;
  String? get appointmentId => _$this._appointmentId;
  set appointmentId(String? appointmentId) =>
      _$this._appointmentId = appointmentId;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  NotificationTargetBuilder() {
    NotificationTarget._defaults(this);
  }

  NotificationTargetBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _bookingId = $v.bookingId;
      _appointmentId = $v.appointmentId;
      _salonId = $v.salonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationTarget other) {
    _$v = other as _$NotificationTarget;
  }

  @override
  void update(void Function(NotificationTargetBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationTarget build() => _build();

  _$NotificationTarget _build() {
    final _$result = _$v ??
        _$NotificationTarget._(
          kind: kind,
          bookingId: bookingId,
          appointmentId: appointmentId,
          salonId: salonId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
