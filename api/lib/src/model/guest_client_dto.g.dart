// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_client_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestClientDto extends GuestClientDto {
  @override
  final String name;
  @override
  final String surname;
  @override
  final String phone;

  factory _$GuestClientDto([void Function(GuestClientDtoBuilder)? updates]) =>
      (GuestClientDtoBuilder()..update(updates))._build();

  _$GuestClientDto._(
      {required this.name, required this.surname, required this.phone})
      : super._();
  @override
  GuestClientDto rebuild(void Function(GuestClientDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestClientDtoBuilder toBuilder() => GuestClientDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestClientDto &&
        name == other.name &&
        surname == other.surname &&
        phone == other.phone;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, surname.hashCode);
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestClientDto')
          ..add('name', name)
          ..add('surname', surname)
          ..add('phone', phone))
        .toString();
  }
}

class GuestClientDtoBuilder
    implements Builder<GuestClientDto, GuestClientDtoBuilder> {
  _$GuestClientDto? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _surname;
  String? get surname => _$this._surname;
  set surname(String? surname) => _$this._surname = surname;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  GuestClientDtoBuilder() {
    GuestClientDto._defaults(this);
  }

  GuestClientDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _surname = $v.surname;
      _phone = $v.phone;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestClientDto other) {
    _$v = other as _$GuestClientDto;
  }

  @override
  void update(void Function(GuestClientDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestClientDto build() => _build();

  _$GuestClientDto _build() {
    final _$result = _$v ??
        _$GuestClientDto._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'GuestClientDto', 'name'),
          surname: BuiltValueNullFieldError.checkNotNull(
              surname, r'GuestClientDto', 'surname'),
          phone: BuiltValueNullFieldError.checkNotNull(
              phone, r'GuestClientDto', 'phone'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
