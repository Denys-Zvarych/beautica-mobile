// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_list_removal_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ClientListRemovalRequest extends ClientListRemovalRequest {
  @override
  final String? clientId;
  @override
  final String? guestBookingId;

  factory _$ClientListRemovalRequest(
          [void Function(ClientListRemovalRequestBuilder)? updates]) =>
      (ClientListRemovalRequestBuilder()..update(updates))._build();

  _$ClientListRemovalRequest._({this.clientId, this.guestBookingId})
      : super._();
  @override
  ClientListRemovalRequest rebuild(
          void Function(ClientListRemovalRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientListRemovalRequestBuilder toBuilder() =>
      ClientListRemovalRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientListRemovalRequest &&
        clientId == other.clientId &&
        guestBookingId == other.guestBookingId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, clientId.hashCode);
    _$hash = $jc(_$hash, guestBookingId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientListRemovalRequest')
          ..add('clientId', clientId)
          ..add('guestBookingId', guestBookingId))
        .toString();
  }
}

class ClientListRemovalRequestBuilder
    implements
        Builder<ClientListRemovalRequest, ClientListRemovalRequestBuilder> {
  _$ClientListRemovalRequest? _$v;

  String? _clientId;
  String? get clientId => _$this._clientId;
  set clientId(String? clientId) => _$this._clientId = clientId;

  String? _guestBookingId;
  String? get guestBookingId => _$this._guestBookingId;
  set guestBookingId(String? guestBookingId) =>
      _$this._guestBookingId = guestBookingId;

  ClientListRemovalRequestBuilder() {
    ClientListRemovalRequest._defaults(this);
  }

  ClientListRemovalRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _clientId = $v.clientId;
      _guestBookingId = $v.guestBookingId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientListRemovalRequest other) {
    _$v = other as _$ClientListRemovalRequest;
  }

  @override
  void update(void Function(ClientListRemovalRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientListRemovalRequest build() => _build();

  _$ClientListRemovalRequest _build() {
    final _$result = _$v ??
        _$ClientListRemovalRequest._(
          clientId: clientId,
          guestBookingId: guestBookingId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
