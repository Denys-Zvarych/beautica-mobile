// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_independent_master_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegisterIndependentMasterRequest
    extends RegisterIndependentMasterRequest {
  @override
  final String? email;
  @override
  final String password;
  @override
  final String firstName;
  @override
  final String? lastName;
  @override
  final String? phoneNumber;
  @override
  final bool? termsAccepted;
  @override
  final String? termsVersion;
  @override
  final String? privacyPolicyVersion;
  @override
  final String? registrationTicket;

  factory _$RegisterIndependentMasterRequest(
          [void Function(RegisterIndependentMasterRequestBuilder)? updates]) =>
      (RegisterIndependentMasterRequestBuilder()..update(updates))._build();

  _$RegisterIndependentMasterRequest._(
      {this.email,
      required this.password,
      required this.firstName,
      this.lastName,
      this.phoneNumber,
      this.termsAccepted,
      this.termsVersion,
      this.privacyPolicyVersion,
      this.registrationTicket})
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
        phoneNumber == other.phoneNumber &&
        termsAccepted == other.termsAccepted &&
        termsVersion == other.termsVersion &&
        privacyPolicyVersion == other.privacyPolicyVersion &&
        registrationTicket == other.registrationTicket;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, termsAccepted.hashCode);
    _$hash = $jc(_$hash, termsVersion.hashCode);
    _$hash = $jc(_$hash, privacyPolicyVersion.hashCode);
    _$hash = $jc(_$hash, registrationTicket.hashCode);
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
          ..add('phoneNumber', phoneNumber)
          ..add('termsAccepted', termsAccepted)
          ..add('termsVersion', termsVersion)
          ..add('privacyPolicyVersion', privacyPolicyVersion)
          ..add('registrationTicket', registrationTicket))
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

  bool? _termsAccepted;
  bool? get termsAccepted => _$this._termsAccepted;
  set termsAccepted(bool? termsAccepted) =>
      _$this._termsAccepted = termsAccepted;

  String? _termsVersion;
  String? get termsVersion => _$this._termsVersion;
  set termsVersion(String? termsVersion) => _$this._termsVersion = termsVersion;

  String? _privacyPolicyVersion;
  String? get privacyPolicyVersion => _$this._privacyPolicyVersion;
  set privacyPolicyVersion(String? privacyPolicyVersion) =>
      _$this._privacyPolicyVersion = privacyPolicyVersion;

  String? _registrationTicket;
  String? get registrationTicket => _$this._registrationTicket;
  set registrationTicket(String? registrationTicket) =>
      _$this._registrationTicket = registrationTicket;

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
      _termsAccepted = $v.termsAccepted;
      _termsVersion = $v.termsVersion;
      _privacyPolicyVersion = $v.privacyPolicyVersion;
      _registrationTicket = $v.registrationTicket;
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
          email: email,
          password: BuiltValueNullFieldError.checkNotNull(
              password, r'RegisterIndependentMasterRequest', 'password'),
          firstName: BuiltValueNullFieldError.checkNotNull(
              firstName, r'RegisterIndependentMasterRequest', 'firstName'),
          lastName: lastName,
          phoneNumber: phoneNumber,
          termsAccepted: termsAccepted,
          termsVersion: termsVersion,
          privacyPolicyVersion: privacyPolicyVersion,
          registrationTicket: registrationTicket,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
