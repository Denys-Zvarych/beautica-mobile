// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AuthResponseRoleEnum _$authResponseRoleEnum_CLIENT =
    const AuthResponseRoleEnum._('CLIENT');
const AuthResponseRoleEnum _$authResponseRoleEnum_SALON_OWNER =
    const AuthResponseRoleEnum._('SALON_OWNER');
const AuthResponseRoleEnum _$authResponseRoleEnum_SALON_ADMIN =
    const AuthResponseRoleEnum._('SALON_ADMIN');
const AuthResponseRoleEnum _$authResponseRoleEnum_SALON_MASTER =
    const AuthResponseRoleEnum._('SALON_MASTER');
const AuthResponseRoleEnum _$authResponseRoleEnum_INDEPENDENT_MASTER =
    const AuthResponseRoleEnum._('INDEPENDENT_MASTER');

AuthResponseRoleEnum _$authResponseRoleEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT':
      return _$authResponseRoleEnum_CLIENT;
    case 'SALON_OWNER':
      return _$authResponseRoleEnum_SALON_OWNER;
    case 'SALON_ADMIN':
      return _$authResponseRoleEnum_SALON_ADMIN;
    case 'SALON_MASTER':
      return _$authResponseRoleEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$authResponseRoleEnum_INDEPENDENT_MASTER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AuthResponseRoleEnum> _$authResponseRoleEnumValues =
    BuiltSet<AuthResponseRoleEnum>(const <AuthResponseRoleEnum>[
  _$authResponseRoleEnum_CLIENT,
  _$authResponseRoleEnum_SALON_OWNER,
  _$authResponseRoleEnum_SALON_ADMIN,
  _$authResponseRoleEnum_SALON_MASTER,
  _$authResponseRoleEnum_INDEPENDENT_MASTER,
]);

Serializer<AuthResponseRoleEnum> _$authResponseRoleEnumSerializer =
    _$AuthResponseRoleEnumSerializer();

class _$AuthResponseRoleEnumSerializer
    implements PrimitiveSerializer<AuthResponseRoleEnum> {
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
  final Iterable<Type> types = const <Type>[AuthResponseRoleEnum];
  @override
  final String wireName = 'AuthResponseRoleEnum';

  @override
  Object serialize(Serializers serializers, AuthResponseRoleEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AuthResponseRoleEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AuthResponseRoleEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AuthResponse extends AuthResponse {
  @override
  final String? accessToken;
  @override
  final String? refreshToken;
  @override
  final String? tokenType;
  @override
  final String? userId;
  @override
  final String? email;
  @override
  final AuthResponseRoleEnum? role;
  @override
  final String? salonId;

  factory _$AuthResponse([void Function(AuthResponseBuilder)? updates]) =>
      (AuthResponseBuilder()..update(updates))._build();

  _$AuthResponse._(
      {this.accessToken,
      this.refreshToken,
      this.tokenType,
      this.userId,
      this.email,
      this.role,
      this.salonId})
      : super._();
  @override
  AuthResponse rebuild(void Function(AuthResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AuthResponseBuilder toBuilder() => AuthResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AuthResponse &&
        accessToken == other.accessToken &&
        refreshToken == other.refreshToken &&
        tokenType == other.tokenType &&
        userId == other.userId &&
        email == other.email &&
        role == other.role &&
        salonId == other.salonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, accessToken.hashCode);
    _$hash = $jc(_$hash, refreshToken.hashCode);
    _$hash = $jc(_$hash, tokenType.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AuthResponse')
          ..add('accessToken', accessToken)
          ..add('refreshToken', refreshToken)
          ..add('tokenType', tokenType)
          ..add('userId', userId)
          ..add('email', email)
          ..add('role', role)
          ..add('salonId', salonId))
        .toString();
  }
}

class AuthResponseBuilder
    implements Builder<AuthResponse, AuthResponseBuilder> {
  _$AuthResponse? _$v;

  String? _accessToken;
  String? get accessToken => _$this._accessToken;
  set accessToken(String? accessToken) => _$this._accessToken = accessToken;

  String? _refreshToken;
  String? get refreshToken => _$this._refreshToken;
  set refreshToken(String? refreshToken) => _$this._refreshToken = refreshToken;

  String? _tokenType;
  String? get tokenType => _$this._tokenType;
  set tokenType(String? tokenType) => _$this._tokenType = tokenType;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  AuthResponseRoleEnum? _role;
  AuthResponseRoleEnum? get role => _$this._role;
  set role(AuthResponseRoleEnum? role) => _$this._role = role;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  AuthResponseBuilder() {
    AuthResponse._defaults(this);
  }

  AuthResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _accessToken = $v.accessToken;
      _refreshToken = $v.refreshToken;
      _tokenType = $v.tokenType;
      _userId = $v.userId;
      _email = $v.email;
      _role = $v.role;
      _salonId = $v.salonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AuthResponse other) {
    _$v = other as _$AuthResponse;
  }

  @override
  void update(void Function(AuthResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AuthResponse build() => _build();

  _$AuthResponse _build() {
    final _$result = _$v ??
        _$AuthResponse._(
          accessToken: accessToken,
          refreshToken: refreshToken,
          tokenType: tokenType,
          userId: userId,
          email: email,
          role: role,
          salonId: salonId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
