// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_appointment_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateAppointmentRequest extends CreateAppointmentRequest {
  @override
  final String masterId;
  @override
  final BuiltList<String> masterServiceIds;
  @override
  final DateTime startsAt;
  @override
  final String? idempotencyKey;
  @override
  final String? clientComment;
  @override
  final bool? allowClientOverlap;

  factory _$CreateAppointmentRequest(
          [void Function(CreateAppointmentRequestBuilder)? updates]) =>
      (CreateAppointmentRequestBuilder()..update(updates))._build();

  _$CreateAppointmentRequest._(
      {required this.masterId,
      required this.masterServiceIds,
      required this.startsAt,
      this.idempotencyKey,
      this.clientComment,
      this.allowClientOverlap})
      : super._();
  @override
  CreateAppointmentRequest rebuild(
          void Function(CreateAppointmentRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateAppointmentRequestBuilder toBuilder() =>
      CreateAppointmentRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateAppointmentRequest &&
        masterId == other.masterId &&
        masterServiceIds == other.masterServiceIds &&
        startsAt == other.startsAt &&
        idempotencyKey == other.idempotencyKey &&
        clientComment == other.clientComment &&
        allowClientOverlap == other.allowClientOverlap;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterServiceIds.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, idempotencyKey.hashCode);
    _$hash = $jc(_$hash, clientComment.hashCode);
    _$hash = $jc(_$hash, allowClientOverlap.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateAppointmentRequest')
          ..add('masterId', masterId)
          ..add('masterServiceIds', masterServiceIds)
          ..add('startsAt', startsAt)
          ..add('idempotencyKey', idempotencyKey)
          ..add('clientComment', clientComment)
          ..add('allowClientOverlap', allowClientOverlap))
        .toString();
  }
}

class CreateAppointmentRequestBuilder
    implements
        Builder<CreateAppointmentRequest, CreateAppointmentRequestBuilder> {
  _$CreateAppointmentRequest? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  ListBuilder<String>? _masterServiceIds;
  ListBuilder<String> get masterServiceIds =>
      _$this._masterServiceIds ??= ListBuilder<String>();
  set masterServiceIds(ListBuilder<String>? masterServiceIds) =>
      _$this._masterServiceIds = masterServiceIds;

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

  CreateAppointmentRequestBuilder() {
    CreateAppointmentRequest._defaults(this);
  }

  CreateAppointmentRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _masterServiceIds = $v.masterServiceIds.toBuilder();
      _startsAt = $v.startsAt;
      _idempotencyKey = $v.idempotencyKey;
      _clientComment = $v.clientComment;
      _allowClientOverlap = $v.allowClientOverlap;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateAppointmentRequest other) {
    _$v = other as _$CreateAppointmentRequest;
  }

  @override
  void update(void Function(CreateAppointmentRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateAppointmentRequest build() => _build();

  _$CreateAppointmentRequest _build() {
    _$CreateAppointmentRequest _$result;
    try {
      _$result = _$v ??
          _$CreateAppointmentRequest._(
            masterId: BuiltValueNullFieldError.checkNotNull(
                masterId, r'CreateAppointmentRequest', 'masterId'),
            masterServiceIds: masterServiceIds.build(),
            startsAt: BuiltValueNullFieldError.checkNotNull(
                startsAt, r'CreateAppointmentRequest', 'startsAt'),
            idempotencyKey: idempotencyKey,
            clientComment: clientComment,
            allowClientOverlap: allowClientOverlap,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'masterServiceIds';
        masterServiceIds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CreateAppointmentRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
