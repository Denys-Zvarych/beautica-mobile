// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_accept_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InviteAcceptRequest extends InviteAcceptRequest {
  @override
  final String token;
  @override
  final String password;
  @override
  final String firstName;
  @override
  final String lastName;
  @override
  final String phoneNumber;
  @override
  final bool? termsAccepted;
  @override
  final String? termsVersion;
  @override
  final String? privacyPolicyVersion;

  factory _$InviteAcceptRequest(
          [void Function(InviteAcceptRequestBuilder)? updates]) =>
      (InviteAcceptRequestBuilder()..update(updates))._build();

  _$InviteAcceptRequest._(
      {required this.token,
      required this.password,
      required this.firstName,
      required this.lastName,
      required this.phoneNumber,
      this.termsAccepted,
      this.termsVersion,
      this.privacyPolicyVersion})
      : super._();
  @override
  InviteAcceptRequest rebuild(
          void Function(InviteAcceptRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InviteAcceptRequestBuilder toBuilder() =>
      InviteAcceptRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InviteAcceptRequest &&
        token == other.token &&
        password == other.password &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        phoneNumber == other.phoneNumber &&
        termsAccepted == other.termsAccepted &&
        termsVersion == other.termsVersion &&
        privacyPolicyVersion == other.privacyPolicyVersion;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, termsAccepted.hashCode);
    _$hash = $jc(_$hash, termsVersion.hashCode);
    _$hash = $jc(_$hash, privacyPolicyVersion.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InviteAcceptRequest')
          ..add('token', token)
          ..add('password', password)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber)
          ..add('termsAccepted', termsAccepted)
          ..add('termsVersion', termsVersion)
          ..add('privacyPolicyVersion', privacyPolicyVersion))
        .toString();
  }
}

class InviteAcceptRequestBuilder
    implements Builder<InviteAcceptRequest, InviteAcceptRequestBuilder> {
  _$InviteAcceptRequest? _$v;

  String? _token;
  String? get token => _$this._token;
  set token(String? token) => _$this._token = token;

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

  InviteAcceptRequestBuilder() {
    InviteAcceptRequest._defaults(this);
  }

  InviteAcceptRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _token = $v.token;
      _password = $v.password;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _phoneNumber = $v.phoneNumber;
      _termsAccepted = $v.termsAccepted;
      _termsVersion = $v.termsVersion;
      _privacyPolicyVersion = $v.privacyPolicyVersion;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InviteAcceptRequest other) {
    _$v = other as _$InviteAcceptRequest;
  }

  @override
  void update(void Function(InviteAcceptRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InviteAcceptRequest build() => _build();

  _$InviteAcceptRequest _build() {
    final _$result = _$v ??
        _$InviteAcceptRequest._(
          token: BuiltValueNullFieldError.checkNotNull(
              token, r'InviteAcceptRequest', 'token'),
          password: BuiltValueNullFieldError.checkNotNull(
              password, r'InviteAcceptRequest', 'password'),
          firstName: BuiltValueNullFieldError.checkNotNull(
              firstName, r'InviteAcceptRequest', 'firstName'),
          lastName: BuiltValueNullFieldError.checkNotNull(
              lastName, r'InviteAcceptRequest', 'lastName'),
          phoneNumber: BuiltValueNullFieldError.checkNotNull(
              phoneNumber, r'InviteAcceptRequest', 'phoneNumber'),
          termsAccepted: termsAccepted,
          termsVersion: termsVersion,
          privacyPolicyVersion: privacyPolicyVersion,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
