// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_booking_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateBookingRequest extends CreateBookingRequest {
  @override
  final String masterId;
  @override
  final String masterServiceId;
  @override
  final DateTime startsAt;
  @override
  final String? idempotencyKey;
  @override
  final String? clientComment;
  @override
  final bool? allowClientOverlap;

  factory _$CreateBookingRequest(
          [void Function(CreateBookingRequestBuilder)? updates]) =>
      (CreateBookingRequestBuilder()..update(updates))._build();

  _$CreateBookingRequest._(
      {required this.masterId,
      required this.masterServiceId,
      required this.startsAt,
      this.idempotencyKey,
      this.clientComment,
      this.allowClientOverlap})
      : super._();
  @override
  CreateBookingRequest rebuild(
          void Function(CreateBookingRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateBookingRequestBuilder toBuilder() =>
      CreateBookingRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateBookingRequest &&
        masterId == other.masterId &&
        masterServiceId == other.masterServiceId &&
        startsAt == other.startsAt &&
        idempotencyKey == other.idempotencyKey &&
        clientComment == other.clientComment &&
        allowClientOverlap == other.allowClientOverlap;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterServiceId.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, idempotencyKey.hashCode);
    _$hash = $jc(_$hash, clientComment.hashCode);
    _$hash = $jc(_$hash, allowClientOverlap.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateBookingRequest')
          ..add('masterId', masterId)
          ..add('masterServiceId', masterServiceId)
          ..add('startsAt', startsAt)
          ..add('idempotencyKey', idempotencyKey)
          ..add('clientComment', clientComment)
          ..add('allowClientOverlap', allowClientOverlap))
        .toString();
  }
}

class CreateBookingRequestBuilder
    implements Builder<CreateBookingRequest, CreateBookingRequestBuilder> {
  _$CreateBookingRequest? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterServiceId;
  String? get masterServiceId => _$this._masterServiceId;
  set masterServiceId(String? masterServiceId) =>
      _$this._masterServiceId = masterServiceId;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  String? _idempotencyKey;
  String? get idempotencyKey => _$this._idempotencyKey;
  set idempotencyKey(String? idempotencyKey) =>
      _$this._idempotencyKey = idempotencyKey;

  String? _clientComment;
  String? get clientComment => _$this._clientComment;
  set clientComment(String? clientComment) =>
      _$this._clientComment = clientComment;

  bool? _allowClientOverlap;
  bool? get allowClientOverlap => _$this._allowClientOverlap;
  set allowClientOverlap(bool? allowClientOverlap) =>
      _$this._allowClientOverlap = allowClientOverlap;

  CreateBookingRequestBuilder() {
    CreateBookingRequest._defaults(this);
  }

  CreateBookingRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _masterServiceId = $v.masterServiceId;
      _startsAt = $v.startsAt;
      _idempotencyKey = $v.idempotencyKey;
      _clientComment = $v.clientComment;
      _allowClientOverlap = $v.allowClientOverlap;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateBookingRequest other) {
    _$v = other as _$CreateBookingRequest;
  }

  @override
  void update(void Function(CreateBookingRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateBookingRequest build() => _build();

  _$CreateBookingRequest _build() {
    final _$result = _$v ??
        _$CreateBookingRequest._(
          masterId: BuiltValueNullFieldError.checkNotNull(
              masterId, r'CreateBookingRequest', 'masterId'),
          masterServiceId: BuiltValueNullFieldError.checkNotNull(
              masterServiceId, r'CreateBookingRequest', 'masterServiceId'),
          startsAt: BuiltValueNullFieldError.checkNotNull(
              startsAt, r'CreateBookingRequest', 'startsAt'),
          idempotencyKey: idempotencyKey,
          clientComment: clientComment,
          allowClientOverlap: allowClientOverlap,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
