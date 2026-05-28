// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_independent_master_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegisterIndependentMasterRequest
    extends RegisterIndependentMasterRequest {
  @override
  final String email;
  @override
  final String password;
  @override
  final String firstName;
  @override
  final String lastName;
  @override
  final String phoneNumber;

  factory _$RegisterIndependentMasterRequest(
          [void Function(RegisterIndependentMasterRequestBuilder)? updates]) =>
      (RegisterIndependentMasterRequestBuilder()..update(updates))._build();

  _$RegisterIndependentMasterRequest._(
      {required this.email,
      required this.password,
      required this.firstName,
      required this.lastName,
      required this.phoneNumber})
      : super._();
  @override
  RegisterIndependentMasterRequest rebuild(
          void Function(RegisterIndependentMasterRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegisterIndependentMasterRequestBuilder toBuilder() =>
      RegisterIndependentMasterRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegisterIndependentMasterRequest &&
        email == other.email &&
        password == other.password &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        phoneNumber == other.phoneNumber;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegisterIndependentMasterRequest')
          ..add('email', email)
          ..add('password', password)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber))
        .toString();
  }
}

class RegisterIndependentMasterRequestBuilder
    implements
        Builder<RegisterIndependentMasterRequest,
            RegisterIndependentMasterRequestBuilder> {
  _$RegisterIndependentMasterRequest? _$v;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _phoneNumber;
  String? get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String? phoneNumber) => _$this._phoneNumber = phoneNumber;

  RegisterIndependentMasterRequestBuilder() {
    RegisterIndependentMasterRequest._defaults(this);
  }

  RegisterIndependentMasterRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _email = $v.email;
      _password = $v.password;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _phoneNumber = $v.phoneNumber;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegisterIndependentMasterRequest other) {
    _$v = other as _$RegisterIndependentMasterRequest;
  }

  @override
  void update(void Function(RegisterIndependentMasterRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegisterIndependentMasterRequest build() => _build();

  _$RegisterIndependentMasterRequest _build() {
    final _$result = _$v ??
        _$RegisterIndependentMasterRequest._(
          email: BuiltValueNullFieldError.checkNotNull(
              email, r'RegisterIndependentMasterRequest', 'email'),
          password: BuiltValueNullFieldError.checkNotNull(
              password, r'RegisterIndependentMasterRequest', 'password'),
          firstName: BuiltValueNullFieldError.checkNotNull(
              firstName, r'RegisterIndependentMasterRequest', 'firstName'),
          lastName: BuiltValueNullFieldError.checkNotNull(
              lastName, r'RegisterIndependentMasterRequest', 'lastName'),
          phoneNumber: BuiltValueNullFieldError.checkNotNull(
              phoneNumber, r'RegisterIndependentMasterRequest', 'phoneNumber'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
