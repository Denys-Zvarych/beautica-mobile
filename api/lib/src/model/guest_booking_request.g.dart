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
  @override
  final bool privacyAccepted;
  @override
  final String privacyPolicyVersion;
  @override
  final String? clientComment;

  factory _$GuestBookingRequest(
          [void Function(GuestBookingRequestBuilder)? updates]) =>
      (GuestBookingRequestBuilder()..update(updates))._build();

  _$GuestBookingRequest._(
      {this.serviceId,
      this.masterServiceIds,
      required this.startsAt,
      required this.name,
      required this.surname,
      required this.privacyAccepted,
      required this.privacyPolicyVersion,
      this.clientComment})
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
        surname == other.surname &&
        privacyAccepted == other.privacyAccepted &&
        privacyPolicyVersion == other.privacyPolicyVersion &&
        clientComment == other.clientComment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, serviceId.hashCode);
    _$hash = $jc(_$hash, masterServiceIds.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, surname.hashCode);
    _$hash = $jc(_$hash, privacyAccepted.hashCode);
    _$hash = $jc(_$hash, privacyPolicyVersion.hashCode);
    _$hash = $jc(_$hash, clientComment.hashCode);
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
          ..add('surname', surname)
          ..add('privacyAccepted', privacyAccepted)
          ..add('privacyPolicyVersion', privacyPolicyVersion)
          ..add('clientComment', clientComment))
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

  bool? _privacyAccepted;
  bool? get privacyAccepted => _$this._privacyAccepted;
  set privacyAccepted(bool? privacyAccepted) =>
      _$this._privacyAccepted = privacyAccepted;

  String? _privacyPolicyVersion;
  String? get privacyPolicyVersion => _$this._privacyPolicyVersion;
  set privacyPolicyVersion(String? privacyPolicyVersion) =>
      _$this._privacyPolicyVersion = privacyPolicyVersion;

  String? _clientComment;
  String? get clientComment => _$this._clientComment;
  set clientComment(String? clientComment) =>
      _$this._clientComment = clientComment;

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
      _privacyAccepted = $v.privacyAccepted;
      _privacyPolicyVersion = $v.privacyPolicyVersion;
      _clientComment = $v.clientComment;
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
            privacyAccepted: BuiltValueNullFieldError.checkNotNull(
                privacyAccepted, r'GuestBookingRequest', 'privacyAccepted'),
            privacyPolicyVersion: BuiltValueNullFieldError.checkNotNull(
                privacyPolicyVersion,
                r'GuestBookingRequest',
                'privacyPolicyVersion'),
            clientComment: clientComment,
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
