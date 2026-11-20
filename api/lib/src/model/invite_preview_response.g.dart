// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_preview_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const InvitePreviewResponseRoleEnum _$invitePreviewResponseRoleEnum_CLIENT =
    const InvitePreviewResponseRoleEnum._('CLIENT');
const InvitePreviewResponseRoleEnum
    _$invitePreviewResponseRoleEnum_SALON_OWNER =
    const InvitePreviewResponseRoleEnum._('SALON_OWNER');
const InvitePreviewResponseRoleEnum
    _$invitePreviewResponseRoleEnum_SALON_ADMIN =
    const InvitePreviewResponseRoleEnum._('SALON_ADMIN');
const InvitePreviewResponseRoleEnum
    _$invitePreviewResponseRoleEnum_SALON_MASTER =
    const InvitePreviewResponseRoleEnum._('SALON_MASTER');
const InvitePreviewResponseRoleEnum
    _$invitePreviewResponseRoleEnum_INDEPENDENT_MASTER =
    const InvitePreviewResponseRoleEnum._('INDEPENDENT_MASTER');
const InvitePreviewResponseRoleEnum
    _$invitePreviewResponseRoleEnum_unknownDefaultOpenApi =
    const InvitePreviewResponseRoleEnum._('unknownDefaultOpenApi');

InvitePreviewResponseRoleEnum _$invitePreviewResponseRoleEnumValueOf(
    String name) {
  switch (name) {
    case 'CLIENT':
      return _$invitePreviewResponseRoleEnum_CLIENT;
    case 'SALON_OWNER':
      return _$invitePreviewResponseRoleEnum_SALON_OWNER;
    case 'SALON_ADMIN':
      return _$invitePreviewResponseRoleEnum_SALON_ADMIN;
    case 'SALON_MASTER':
      return _$invitePreviewResponseRoleEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$invitePreviewResponseRoleEnum_INDEPENDENT_MASTER;
    case 'unknownDefaultOpenApi':
      return _$invitePreviewResponseRoleEnum_unknownDefaultOpenApi;
    default:
      return _$invitePreviewResponseRoleEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<InvitePreviewResponseRoleEnum>
    _$invitePreviewResponseRoleEnumValues = BuiltSet<
        InvitePreviewResponseRoleEnum>(const <InvitePreviewResponseRoleEnum>[
  _$invitePreviewResponseRoleEnum_CLIENT,
  _$invitePreviewResponseRoleEnum_SALON_OWNER,
  _$invitePreviewResponseRoleEnum_SALON_ADMIN,
  _$invitePreviewResponseRoleEnum_SALON_MASTER,
  _$invitePreviewResponseRoleEnum_INDEPENDENT_MASTER,
  _$invitePreviewResponseRoleEnum_unknownDefaultOpenApi,
]);

Serializer<InvitePreviewResponseRoleEnum>
    _$invitePreviewResponseRoleEnumSerializer =
    _$InvitePreviewResponseRoleEnumSerializer();

class _$InvitePreviewResponseRoleEnumSerializer
    implements PrimitiveSerializer<InvitePreviewResponseRoleEnum> {
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
  final Iterable<Type> types = const <Type>[InvitePreviewResponseRoleEnum];
  @override
  final String wireName = 'InvitePreviewResponseRoleEnum';

  @override
  Object serialize(
          Serializers serializers, InvitePreviewResponseRoleEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  InvitePreviewResponseRoleEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      InvitePreviewResponseRoleEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$InvitePreviewResponse extends InvitePreviewResponse {
  @override
  final String? phoneMasked;
  @override
  final InvitePreviewResponseRoleEnum? role;
  @override
  final String? salonName;
  @override
  final DateTime? expiresAt;

  factory _$InvitePreviewResponse(
          [void Function(InvitePreviewResponseBuilder)? updates]) =>
      (InvitePreviewResponseBuilder()..update(updates))._build();

  _$InvitePreviewResponse._(
      {this.phoneMasked, this.role, this.salonName, this.expiresAt})
      : super._();
  @override
  InvitePreviewResponse rebuild(
          void Function(InvitePreviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InvitePreviewResponseBuilder toBuilder() =>
      InvitePreviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InvitePreviewResponse &&
        phoneMasked == other.phoneMasked &&
        role == other.role &&
        salonName == other.salonName &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, phoneMasked.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, salonName.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InvitePreviewResponse')
          ..add('phoneMasked', phoneMasked)
          ..add('role', role)
          ..add('salonName', salonName)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class InvitePreviewResponseBuilder
    implements Builder<InvitePreviewResponse, InvitePreviewResponseBuilder> {
  _$InvitePreviewResponse? _$v;

  String? _phoneMasked;
  String? get phoneMasked => _$this._phoneMasked;
  set phoneMasked(String? phoneMasked) => _$this._phoneMasked = phoneMasked;

  InvitePreviewResponseRoleEnum? _role;
  InvitePreviewResponseRoleEnum? get role => _$this._role;
  set role(InvitePreviewResponseRoleEnum? role) => _$this._role = role;

  String? _salonName;
  String? get salonName => _$this._salonName;
  set salonName(String? salonName) => _$this._salonName = salonName;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  InvitePreviewResponseBuilder() {
    InvitePreviewResponse._defaults(this);
  }

  InvitePreviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phoneMasked = $v.phoneMasked;
      _role = $v.role;
      _salonName = $v.salonName;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InvitePreviewResponse other) {
    _$v = other as _$InvitePreviewResponse;
  }

  @override
  void update(void Function(InvitePreviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InvitePreviewResponse build() => _build();

  _$InvitePreviewResponse _build() {
    final _$result = _$v ??
        _$InvitePreviewResponse._(
          phoneMasked: phoneMasked,
          role: role,
          salonName: salonName,
          expiresAt: expiresAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
