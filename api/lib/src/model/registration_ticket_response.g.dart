// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registration_ticket_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegistrationTicketResponse extends RegistrationTicketResponse {
  @override
  final String? registrationTicket;

  factory _$RegistrationTicketResponse(
          [void Function(RegistrationTicketResponseBuilder)? updates]) =>
      (RegistrationTicketResponseBuilder()..update(updates))._build();

  _$RegistrationTicketResponse._({this.registrationTicket}) : super._();
  @override
  RegistrationTicketResponse rebuild(
          void Function(RegistrationTicketResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegistrationTicketResponseBuilder toBuilder() =>
      RegistrationTicketResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegistrationTicketResponse &&
        registrationTicket == other.registrationTicket;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, registrationTicket.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegistrationTicketResponse')
          ..add('registrationTicket', registrationTicket))
        .toString();
  }
}

class RegistrationTicketResponseBuilder
    implements
        Builder<RegistrationTicketResponse, RegistrationTicketResponseBuilder> {
  _$RegistrationTicketResponse? _$v;

  String? _registrationTicket;
  String? get registrationTicket => _$this._registrationTicket;
  set registrationTicket(String? registrationTicket) =>
      _$this._registrationTicket = registrationTicket;

  RegistrationTicketResponseBuilder() {
    RegistrationTicketResponse._defaults(this);
  }

  RegistrationTicketResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _registrationTicket = $v.registrationTicket;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegistrationTicketResponse other) {
    _$v = other as _$RegistrationTicketResponse;
  }

  @override
  void update(void Function(RegistrationTicketResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegistrationTicketResponse build() => _build();

  _$RegistrationTicketResponse _build() {
    final _$result = _$v ??
        _$RegistrationTicketResponse._(
          registrationTicket: registrationTicket,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
