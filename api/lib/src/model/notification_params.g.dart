// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_params.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const NotificationParamsSubjectRoleEnum
    _$notificationParamsSubjectRoleEnum_CLIENT =
    const NotificationParamsSubjectRoleEnum._('CLIENT');
const NotificationParamsSubjectRoleEnum
    _$notificationParamsSubjectRoleEnum_SALON_OWNER =
    const NotificationParamsSubjectRoleEnum._('SALON_OWNER');
const NotificationParamsSubjectRoleEnum
    _$notificationParamsSubjectRoleEnum_SALON_ADMIN =
    const NotificationParamsSubjectRoleEnum._('SALON_ADMIN');
const NotificationParamsSubjectRoleEnum
    _$notificationParamsSubjectRoleEnum_SALON_MASTER =
    const NotificationParamsSubjectRoleEnum._('SALON_MASTER');
const NotificationParamsSubjectRoleEnum
    _$notificationParamsSubjectRoleEnum_INDEPENDENT_MASTER =
    const NotificationParamsSubjectRoleEnum._('INDEPENDENT_MASTER');
const NotificationParamsSubjectRoleEnum
    _$notificationParamsSubjectRoleEnum_unknownDefaultOpenApi =
    const NotificationParamsSubjectRoleEnum._('unknownDefaultOpenApi');

NotificationParamsSubjectRoleEnum _$notificationParamsSubjectRoleEnumValueOf(
    String name) {
  switch (name) {
    case 'CLIENT':
      return _$notificationParamsSubjectRoleEnum_CLIENT;
    case 'SALON_OWNER':
      return _$notificationParamsSubjectRoleEnum_SALON_OWNER;
    case 'SALON_ADMIN':
      return _$notificationParamsSubjectRoleEnum_SALON_ADMIN;
    case 'SALON_MASTER':
      return _$notificationParamsSubjectRoleEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$notificationParamsSubjectRoleEnum_INDEPENDENT_MASTER;
    case 'unknownDefaultOpenApi':
      return _$notificationParamsSubjectRoleEnum_unknownDefaultOpenApi;
    default:
      return _$notificationParamsSubjectRoleEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<NotificationParamsSubjectRoleEnum>
    _$notificationParamsSubjectRoleEnumValues = BuiltSet<
        NotificationParamsSubjectRoleEnum>(const <NotificationParamsSubjectRoleEnum>[
  _$notificationParamsSubjectRoleEnum_CLIENT,
  _$notificationParamsSubjectRoleEnum_SALON_OWNER,
  _$notificationParamsSubjectRoleEnum_SALON_ADMIN,
  _$notificationParamsSubjectRoleEnum_SALON_MASTER,
  _$notificationParamsSubjectRoleEnum_INDEPENDENT_MASTER,
  _$notificationParamsSubjectRoleEnum_unknownDefaultOpenApi,
]);

Serializer<NotificationParamsSubjectRoleEnum>
    _$notificationParamsSubjectRoleEnumSerializer =
    _$NotificationParamsSubjectRoleEnumSerializer();

class _$NotificationParamsSubjectRoleEnumSerializer
    implements PrimitiveSerializer<NotificationParamsSubjectRoleEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CLIENT': 'CLIENT',
    'SALON_OWNER': 'SALON_OWNER',
    'SALON_ADMIN': 'SALON_ADMIN',
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CLIENT': 'CLIENT',
    'SALON_OWNER': 'SALON_OWNER',
    'SALON_ADMIN': 'SALON_ADMIN',
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[NotificationParamsSubjectRoleEnum];
  @override
  final String wireName = 'NotificationParamsSubjectRoleEnum';

  @override
  Object serialize(
          Serializers serializers, NotificationParamsSubjectRoleEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  NotificationParamsSubjectRoleEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      NotificationParamsSubjectRoleEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$NotificationParams extends NotificationParams {
  @override
  final String? counterpartName;
  @override
  final String? serviceName;
  @override
  final int? serviceCount;
  @override
  final DateTime? startsAt;
  @override
  final String? salonName;
  @override
  final String? subjectName;
  @override
  final NotificationParamsSubjectRoleEnum? subjectRole;

  factory _$NotificationParams(
          [void Function(NotificationParamsBuilder)? updates]) =>
      (NotificationParamsBuilder()..update(updates))._build();

  _$NotificationParams._(
      {this.counterpartName,
      this.serviceName,
      this.serviceCount,
      this.startsAt,
      this.salonName,
      this.subjectName,
      this.subjectRole})
      : super._();
  @override
  NotificationParams rebuild(
          void Function(NotificationParamsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NotificationParamsBuilder toBuilder() =>
      NotificationParamsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationParams &&
        counterpartName == other.counterpartName &&
        serviceName == other.serviceName &&
        serviceCount == other.serviceCount &&
        startsAt == other.startsAt &&
        salonName == other.salonName &&
        subjectName == other.subjectName &&
        subjectRole == other.subjectRole;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, counterpartName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, serviceCount.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, salonName.hashCode);
    _$hash = $jc(_$hash, subjectName.hashCode);
    _$hash = $jc(_$hash, subjectRole.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationParams')
          ..add('counterpartName', counterpartName)
          ..add('serviceName', serviceName)
          ..add('serviceCount', serviceCount)
          ..add('startsAt', startsAt)
          ..add('salonName', salonName)
          ..add('subjectName', subjectName)
          ..add('subjectRole', subjectRole))
        .toString();
  }
}

class NotificationParamsBuilder
    implements Builder<NotificationParams, NotificationParamsBuilder> {
  _$NotificationParams? _$v;

  String? _counterpartName;
  String? get counterpartName => _$this._counterpartName;
  set counterpartName(String? counterpartName) =>
      _$this._counterpartName = counterpartName;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  int? _serviceCount;
  int? get serviceCount => _$this._serviceCount;
  set serviceCount(int? serviceCount) => _$this._serviceCount = serviceCount;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  String? _salonName;
  String? get salonName => _$this._salonName;
  set salonName(String? salonName) => _$this._salonName = salonName;

  String? _subjectName;
  String? get subjectName => _$this._subjectName;
  set subjectName(String? subjectName) => _$this._subjectName = subjectName;

  NotificationParamsSubjectRoleEnum? _subjectRole;
  NotificationParamsSubjectRoleEnum? get subjectRole => _$this._subjectRole;
  set subjectRole(NotificationParamsSubjectRoleEnum? subjectRole) =>
      _$this._subjectRole = subjectRole;

  NotificationParamsBuilder() {
    NotificationParams._defaults(this);
  }

  NotificationParamsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _counterpartName = $v.counterpartName;
      _serviceName = $v.serviceName;
      _serviceCount = $v.serviceCount;
      _startsAt = $v.startsAt;
      _salonName = $v.salonName;
      _subjectName = $v.subjectName;
      _subjectRole = $v.subjectRole;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationParams other) {
    _$v = other as _$NotificationParams;
  }

  @override
  void update(void Function(NotificationParamsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationParams build() => _build();

  _$NotificationParams _build() {
    final _$result = _$v ??
        _$NotificationParams._(
          counterpartName: counterpartName,
          serviceName: serviceName,
          serviceCount: serviceCount,
          startsAt: startsAt,
          salonName: salonName,
          subjectName: subjectName,
          subjectRole: subjectRole,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
