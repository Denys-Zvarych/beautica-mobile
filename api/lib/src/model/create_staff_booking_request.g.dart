// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_staff_booking_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateStaffBookingRequest extends CreateStaffBookingRequest {
  @override
  final BuiltList<String> masterServiceIds;
  @override
  final DateTime startsAt;
  @override
  final GuestClientDto guest;

  factory _$CreateStaffBookingRequest(
          [void Function(CreateStaffBookingRequestBuilder)? updates]) =>
      (CreateStaffBookingRequestBuilder()..update(updates))._build();

  _$CreateStaffBookingRequest._(
      {required this.masterServiceIds,
      required this.startsAt,
      required this.guest})
      : super._();
  @override
  CreateStaffBookingRequest rebuild(
          void Function(CreateStaffBookingRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateStaffBookingRequestBuilder toBuilder() =>
      CreateStaffBookingRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateStaffBookingRequest &&
        masterServiceIds == other.masterServiceIds &&
        startsAt == other.startsAt &&
        guest == other.guest;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterServiceIds.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, guest.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateStaffBookingRequest')
          ..add('masterServiceIds', masterServiceIds)
          ..add('startsAt', startsAt)
          ..add('guest', guest))
        .toString();
  }
}

class CreateStaffBookingRequestBuilder
    implements
        Builder<CreateStaffBookingRequest, CreateStaffBookingRequestBuilder> {
  _$CreateStaffBookingRequest? _$v;

  ListBuilder<String>? _masterServiceIds;
  ListBuilder<String> get masterServiceIds =>
      _$this._masterServiceIds ??= ListBuilder<String>();
  set masterServiceIds(ListBuilder<String>? masterServiceIds) =>
      _$this._masterServiceIds = masterServiceIds;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  GuestClientDtoBuilder? _guest;
  GuestClientDtoBuilder get guest => _$this._guest ??= GuestClientDtoBuilder();
  set guest(GuestClientDtoBuilder? guest) => _$this._guest = guest;

  CreateStaffBookingRequestBuilder() {
    CreateStaffBookingRequest._defaults(this);
  }

  CreateStaffBookingRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterServiceIds = $v.masterServiceIds.toBuilder();
      _startsAt = $v.startsAt;
      _guest = $v.guest.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateStaffBookingRequest other) {
    _$v = other as _$CreateStaffBookingRequest;
  }

  @override
  void update(void Function(CreateStaffBookingRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateStaffBookingRequest build() => _build();

  _$CreateStaffBookingRequest _build() {
    _$CreateStaffBookingRequest _$result;
    try {
      _$result = _$v ??
          _$CreateStaffBookingRequest._(
            masterServiceIds: masterServiceIds.build(),
            startsAt: BuiltValueNullFieldError.checkNotNull(
                startsAt, r'CreateStaffBookingRequest', 'startsAt'),
            guest: guest.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'masterServiceIds';
        masterServiceIds.build();

        _$failedField = 'guest';
        guest.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CreateStaffBookingRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
