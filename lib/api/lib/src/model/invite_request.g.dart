// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const InviteRequestRoleEnum _$inviteRequestRoleEnum_CLIENT =
    const InviteRequestRoleEnum._('CLIENT');
const InviteRequestRoleEnum _$inviteRequestRoleEnum_SALON_OWNER =
    const InviteRequestRoleEnum._('SALON_OWNER');
const InviteRequestRoleEnum _$inviteRequestRoleEnum_SALON_ADMIN =
    const InviteRequestRoleEnum._('SALON_ADMIN');
const InviteRequestRoleEnum _$inviteRequestRoleEnum_SALON_MASTER =
    const InviteRequestRoleEnum._('SALON_MASTER');
const InviteRequestRoleEnum _$inviteRequestRoleEnum_INDEPENDENT_MASTER =
    const InviteRequestRoleEnum._('INDEPENDENT_MASTER');

InviteRequestRoleEnum _$inviteRequestRoleEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT':
      return _$inviteRequestRoleEnum_CLIENT;
    case 'SALON_OWNER':
      return _$inviteRequestRoleEnum_SALON_OWNER;
    case 'SALON_ADMIN':
      return _$inviteRequestRoleEnum_SALON_ADMIN;
    case 'SALON_MASTER':
      return _$inviteRequestRoleEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$inviteRequestRoleEnum_INDEPENDENT_MASTER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<InviteRequestRoleEnum> _$inviteRequestRoleEnumValues =
    BuiltSet<InviteRequestRoleEnum>(const <InviteRequestRoleEnum>[
  _$inviteRequestRoleEnum_CLIENT,
  _$inviteRequestRoleEnum_SALON_OWNER,
  _$inviteRequestRoleEnum_SALON_ADMIN,
  _$inviteRequestRoleEnum_SALON_MASTER,
  _$inviteRequestRoleEnum_INDEPENDENT_MASTER,
]);

Serializer<InviteRequestRoleEnum> _$inviteRequestRoleEnumSerializer =
    _$InviteRequestRoleEnumSerializer();

class _$InviteRequestRoleEnumSerializer
    implements PrimitiveSerializer<InviteRequestRoleEnum> {
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
  final Iterable<Type> types = const <Type>[InviteRequestRoleEnum];
  @override
  final String wireName = 'InviteRequestRoleEnum';

  @override
  Object serialize(Serializers serializers, InviteRequestRoleEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  InviteRequestRoleEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      InviteRequestRoleEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$InviteRequest extends InviteRequest {
  @override
  final String email;
  @override
  final InviteRequestRoleEnum? role;
  @override
  final bool? roleAllowed;

  factory _$InviteRequest([void Function(InviteRequestBuilder)? updates]) =>
      (InviteRequestBuilder()..update(updates))._build();

  _$InviteRequest._({required this.email, this.role, this.roleAllowed})
      : super._();
  @override
  InviteRequest rebuild(void Function(InviteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InviteRequestBuilder toBuilder() => InviteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InviteRequest &&
        email == other.email &&
        role == other.role &&
        roleAllowed == other.roleAllowed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, roleAllowed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InviteRequest')
          ..add('email', email)
          ..add('role', role)
          ..add('roleAllowed', roleAllowed))
        .toString();
  }
}

class InviteRequestBuilder
    implements Builder<InviteRequest, InviteRequestBuilder> {
  _$InviteRequest? _$v;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  InviteRequestRoleEnum? _role;
  InviteRequestRoleEnum? get role => _$this._role;
  set role(InviteRequestRoleEnum? role) => _$this._role = role;

  bool? _roleAllowed;
  bool? get roleAllowed => _$this._roleAllowed;
  set roleAllowed(bool? roleAllowed) => _$this._roleAllowed = roleAllowed;

  InviteRequestBuilder() {
    InviteRequest._defaults(this);
  }

  InviteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _email = $v.email;
      _role = $v.role;
      _roleAllowed = $v.roleAllowed;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InviteRequest other) {
    _$v = other as _$InviteRequest;
  }

  @override
  void update(void Function(InviteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InviteRequest build() => _build();

  _$InviteRequest _build() {
    final _$result = _$v ??
        _$InviteRequest._(
          email: BuiltValueNullFieldError.checkNotNull(
              email, r'InviteRequest', 'email'),
          role: role,
          roleAllowed: roleAllowed,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
