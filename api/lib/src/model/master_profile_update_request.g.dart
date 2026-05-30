// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_profile_update_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MasterProfileUpdateRequest extends MasterProfileUpdateRequest {
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? phoneNumber;
  @override
  final String? bio;
  @override
  final String? instagram;

  factory _$MasterProfileUpdateRequest(
          [void Function(MasterProfileUpdateRequestBuilder)? updates]) =>
      (MasterProfileUpdateRequestBuilder()..update(updates))._build();

  _$MasterProfileUpdateRequest._(
      {this.firstName,
      this.lastName,
      this.phoneNumber,
      this.bio,
      this.instagram})
      : super._();
  @override
  MasterProfileUpdateRequest rebuild(
          void Function(MasterProfileUpdateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterProfileUpdateRequestBuilder toBuilder() =>
      MasterProfileUpdateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterProfileUpdateRequest &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        phoneNumber == other.phoneNumber &&
        bio == other.bio &&
        instagram == other.instagram;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, phoneNumber.hashCode);
    _$hash = $jc(_$hash, bio.hashCode);
    _$hash = $jc(_$hash, instagram.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterProfileUpdateRequest')
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber)
          ..add('bio', bio)
          ..add('instagram', instagram))
        .toString();
  }
}

class MasterProfileUpdateRequestBuilder
    implements
        Builder<MasterProfileUpdateRequest, MasterProfileUpdateRequestBuilder> {
  _$MasterProfileUpdateRequest? _$v;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _phoneNumber;
  String? get phoneNumber => _$this._phoneNumber;
  set phoneNumber(String? phoneNumber) => _$this._phoneNumber = phoneNumber;

  String? _bio;
  String? get bio => _$this._bio;
  set bio(String? bio) => _$this._bio = bio;

  String? _instagram;
  String? get instagram => _$this._instagram;
  set instagram(String? instagram) => _$this._instagram = instagram;

  MasterProfileUpdateRequestBuilder() {
    MasterProfileUpdateRequest._defaults(this);
  }

  MasterProfileUpdateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _phoneNumber = $v.phoneNumber;
      _bio = $v.bio;
      _instagram = $v.instagram;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MasterProfileUpdateRequest other) {
    _$v = other as _$MasterProfileUpdateRequest;
  }

  @override
  void update(void Function(MasterProfileUpdateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterProfileUpdateRequest build() => _build();

  _$MasterProfileUpdateRequest _build() {
    final _$result = _$v ??
        _$MasterProfileUpdateRequest._(
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phoneNumber,
          bio: bio,
          instagram: instagram,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
