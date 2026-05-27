// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const RegisterRequestRoleEnum _$registerRequestRoleEnum_CLIENT =
    const RegisterRequestRoleEnum._('CLIENT');
const RegisterRequestRoleEnum _$registerRequestRoleEnum_SALON_OWNER =
    const RegisterRequestRoleEnum._('SALON_OWNER');

RegisterRequestRoleEnum _$registerRequestRoleEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT':
      return _$registerRequestRoleEnum_CLIENT;
    case 'SALON_OWNER':
      return _$registerRequestRoleEnum_SALON_OWNER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RegisterRequestRoleEnum> _$registerRequestRoleEnumValues =
    BuiltSet<RegisterRequestRoleEnum>(const <RegisterRequestRoleEnum>[
  _$registerRequestRoleEnum_CLIENT,
  _$registerRequestRoleEnum_SALON_OWNER,
]);

Serializer<RegisterRequestRoleEnum> _$registerRequestRoleEnumSerializer =
    _$RegisterRequestRoleEnumSerializer();

class _$RegisterRequestRoleEnumSerializer
    implements PrimitiveSerializer<RegisterRequestRoleEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CLIENT': 'CLIENT',
    'SALON_OWNER': 'SALON_OWNER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CLIENT': 'CLIENT',
    'SALON_OWNER': 'SALON_OWNER',
  };

  @override
  final Iterable<Type> types = const <Type>[RegisterRequestRoleEnum];
  @override
  final String wireName = 'RegisterRequestRoleEnum';

  @override
  Object serialize(Serializers serializers, RegisterRequestRoleEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RegisterRequestRoleEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RegisterRequestRoleEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$RegisterRequest extends RegisterRequest {
  @override
  final String email;
  @override
  final String password;
  @override
  final RegisterRequestRoleEnum role;
  @override
  final String firstName;
  @override
  final String lastName;
  @override
  final String phoneNumber;
  @override
  final String? businessName;

  factory _$RegisterRequest([void Function(RegisterRequestBuilder)? updates]) =>
      (RegisterRequestBuilder()..update(updates))._build();

  _$RegisterRequest._(
      {required this.email,
      required this.password,
      required this.role,
      required this.firstName,
      required this.lastName,
      required this.phoneNumber,
      this.businessName})
      : super._();
  @override
  RegisterRequest rebuild(void Function(RegisterRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegisterRequestBuilder toBuilder() => RegisterRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegisterRequest &&
        email == other.email &&
        password == other.password &&
        role == other.role &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        phoneNumber == other.phoneNumber &&
        businessName == other.businessName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, businessName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegisterRequest')
          ..add('email', email)
          ..add('password', password)
          ..add('role', role)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber)
          ..add('businessName', businessName))
        .toString();
  }
}

class RegisterRequestBuilder
    implements Builder<RegisterRequest, RegisterRequestBuilder> {
  _$RegisterRequest? _$v;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  RegisterRequestRoleEnum? _role;
  RegisterRequestRoleEnum? get role => _$this._role;
  set role(RegisterRequestRoleEnum? role) => _$this._role = role;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _phoneNumber;
  String? get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String? phoneNumber) => _$this._phoneNumber = phoneNumber;

  String? _businessName;
  String? get businessName => _$this._businessName;
  set businessName(String? businessName) => _$this._businessName = businessName;

  RegisterRequestBuilder() {
    RegisterRequest._defaults(this);
  }

  RegisterRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _email = $v.email;
      _password = $v.password;
      _role = $v.role;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _phoneNumber = $v.phoneNumber;
      _businessName = $v.businessName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegisterRequest other) {
    _$v = other as _$RegisterRequest;
  }

  @override
  void update(void Function(RegisterRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegisterRequest build() => _build();

  _$RegisterRequest _build() {
    final _$result = _$v ??
        _$RegisterRequest._(
          email: BuiltValueNullFieldError.checkNotNull(
              email, r'RegisterRequest', 'email'),
          password: BuiltValueNullFieldError.checkNotNull(
              password, r'RegisterRequest', 'password'),
          role: BuiltValueNullFieldError.checkNotNull(
              role, r'RegisterRequest', 'role'),
          firstName: BuiltValueNullFieldError.checkNotNull(
              firstName, r'RegisterRequest', 'firstName'),
          lastName: BuiltValueNullFieldError.checkNotNull(
              lastName, r'RegisterRequest', 'lastName'),
          phoneNumber: BuiltValueNullFieldError.checkNotNull(
              phoneNumber, r'RegisterRequest', 'phoneNumber'),
          businessName: businessName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
