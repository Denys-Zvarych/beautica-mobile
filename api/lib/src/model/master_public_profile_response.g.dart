// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_public_profile_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MasterPublicProfileResponse extends MasterPublicProfileResponse {
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

  factory _$MasterPublicProfileResponse(
          [void Function(MasterPublicProfileResponseBuilder)? updates]) =>
      (MasterPublicProfileResponseBuilder()..update(updates))._build();

  _$MasterPublicProfileResponse._(
      {this.firstName,
      this.lastName,
      this.phoneNumber,
      this.bio,
      this.instagram})
      : super._();
  @override
  MasterPublicProfileResponse rebuild(
          void Function(MasterPublicProfileResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterPublicProfileResponseBuilder toBuilder() =>
      MasterPublicProfileResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterPublicProfileResponse &&
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
    return (newBuiltValueToStringHelper(r'MasterPublicProfileResponse')
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('phoneNumber', phoneNumber)
          ..add('bio', bio)
          ..add('instagram', instagram))
        .toString();
  }
}

class MasterPublicProfileResponseBuilder
    implements
        Builder<MasterPublicProfileResponse,
            MasterPublicProfileResponseBuilder> {
  _$MasterPublicProfileResponse? _$v;

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

  MasterPublicProfileResponseBuilder() {
    MasterPublicProfileResponse._defaults(this);
  }

  MasterPublicProfileResponseBuilder get _$this {
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
  void replace(MasterPublicProfileResponse other) {
    _$v = other as _$MasterPublicProfileResponse;
  }

  @override
  void update(void Function(MasterPublicProfileResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterPublicProfileResponse build() => _build();

  _$MasterPublicProfileResponse _build() {
    final _$result = _$v ??
        _$MasterPublicProfileResponse._(
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
