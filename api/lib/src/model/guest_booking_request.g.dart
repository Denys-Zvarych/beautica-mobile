// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_booking_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestBookingRequest extends GuestBookingRequest {
  @override
  final String? serviceId;
  @override
  final BuiltList<String>? masterServiceIds;
  @override
  final DateTime startsAt;
  @override
  final String name;
  @override
  final String surname;

  factory _$GuestBookingRequest(
          [void Function(GuestBookingRequestBuilder)? updates]) =>
      (GuestBookingRequestBuilder()..update(updates))._build();

  _$GuestBookingRequest._(
      {this.serviceId,
      this.masterServiceIds,
      required this.startsAt,
      required this.name,
      required this.surname})
      : super._();
  @override
  GuestBookingRequest rebuild(
          void Function(GuestBookingRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestBookingRequestBuilder toBuilder() =>
      GuestBookingRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestBookingRequest &&
        serviceId == other.serviceId &&
        masterServiceIds == other.masterServiceIds &&
        startsAt == other.startsAt &&
        name == other.name &&
        surname == other.surname;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, serviceId.hashCode);
    _$hash = $jc(_$hash, masterServiceIds.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, surname.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestBookingRequest')
          ..add('serviceId', serviceId)
          ..add('masterServiceIds', masterServiceIds)
          ..add('startsAt', startsAt)
          ..add('name', name)
          ..add('surname', surname))
        .toString();
  }
}

class GuestBookingRequestBuilder
    implements Builder<GuestBookingRequest, GuestBookingRequestBuilder> {
  _$GuestBookingRequest? _$v;

  String? _serviceId;
  String? get serviceId => _$this._serviceId;
  set serviceId(String? serviceId) => _$this._serviceId = serviceId;

  ListBuilder<String>? _masterServiceIds;
  ListBuilder<String> get masterServiceIds =>
      _$this._masterServiceIds ??= ListBuilder<String>();
  set masterServiceIds(ListBuilder<String>? masterServiceIds) =>
      _$this._masterServiceIds = masterServiceIds;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _surname;
  String? get surname => _$this._surname;
  set surname(String? surname) => _$this._surname = surname;

  GuestBookingRequestBuilder() {
    GuestBookingRequest._defaults(this);
  }

  GuestBookingRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _serviceId = $v.serviceId;
      _masterServiceIds = $v.masterServiceIds?.toBuilder();
      _startsAt = $v.startsAt;
      _name = $v.name;
      _surname = $v.surname;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestBookingRequest other) {
    _$v = other as _$GuestBookingRequest;
  }

  @override
  void update(void Function(GuestBookingRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestBookingRequest build() => _build();

  _$GuestBookingRequest _build() {
    _$GuestBookingRequest _$result;
    try {
      _$result = _$v ??
          _$GuestBookingRequest._(
            serviceId: serviceId,
            masterServiceIds: _masterServiceIds?.build(),
            startsAt: BuiltValueNullFieldError.checkNotNull(
                startsAt, r'GuestBookingRequest', 'startsAt'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'GuestBookingRequest', 'name'),
            surname: BuiltValueNullFieldError.checkNotNull(
                surname, r'GuestBookingRequest', 'surname'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'masterServiceIds';
        _masterServiceIds?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'GuestBookingRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
