// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cancel_token_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CancelTokenItemResponseStatusEnum
    _$cancelTokenItemResponseStatusEnum_CONFIRMED =
    const CancelTokenItemResponseStatusEnum._('CONFIRMED');
const CancelTokenItemResponseStatusEnum
    _$cancelTokenItemResponseStatusEnum_DECLINED =
    const CancelTokenItemResponseStatusEnum._('DECLINED');
const CancelTokenItemResponseStatusEnum
    _$cancelTokenItemResponseStatusEnum_COMPLETED =
    const CancelTokenItemResponseStatusEnum._('COMPLETED');
const CancelTokenItemResponseStatusEnum
    _$cancelTokenItemResponseStatusEnum_NOT_COMPLETED =
    const CancelTokenItemResponseStatusEnum._('NOT_COMPLETED');
const CancelTokenItemResponseStatusEnum
    _$cancelTokenItemResponseStatusEnum_CANCELLED =
    const CancelTokenItemResponseStatusEnum._('CANCELLED');
const CancelTokenItemResponseStatusEnum
    _$cancelTokenItemResponseStatusEnum_unknownDefaultOpenApi =
    const CancelTokenItemResponseStatusEnum._('unknownDefaultOpenApi');

CancelTokenItemResponseStatusEnum _$cancelTokenItemResponseStatusEnumValueOf(
    String name) {
  switch (name) {
    case 'CONFIRMED':
      return _$cancelTokenItemResponseStatusEnum_CONFIRMED;
    case 'DECLINED':
      return _$cancelTokenItemResponseStatusEnum_DECLINED;
    case 'COMPLETED':
      return _$cancelTokenItemResponseStatusEnum_COMPLETED;
    case 'NOT_COMPLETED':
      return _$cancelTokenItemResponseStatusEnum_NOT_COMPLETED;
    case 'CANCELLED':
      return _$cancelTokenItemResponseStatusEnum_CANCELLED;
    case 'unknownDefaultOpenApi':
      return _$cancelTokenItemResponseStatusEnum_unknownDefaultOpenApi;
    default:
      return _$cancelTokenItemResponseStatusEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<CancelTokenItemResponseStatusEnum>
    _$cancelTokenItemResponseStatusEnumValues = BuiltSet<
        CancelTokenItemResponseStatusEnum>(const <CancelTokenItemResponseStatusEnum>[
  _$cancelTokenItemResponseStatusEnum_CONFIRMED,
  _$cancelTokenItemResponseStatusEnum_DECLINED,
  _$cancelTokenItemResponseStatusEnum_COMPLETED,
  _$cancelTokenItemResponseStatusEnum_NOT_COMPLETED,
  _$cancelTokenItemResponseStatusEnum_CANCELLED,
  _$cancelTokenItemResponseStatusEnum_unknownDefaultOpenApi,
]);

Serializer<CancelTokenItemResponseStatusEnum>
    _$cancelTokenItemResponseStatusEnumSerializer =
    _$CancelTokenItemResponseStatusEnumSerializer();

class _$CancelTokenItemResponseStatusEnumSerializer
    implements PrimitiveSerializer<CancelTokenItemResponseStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CONFIRMED': 'CONFIRMED',
    'DECLINED': 'DECLINED',
    'COMPLETED': 'COMPLETED',
    'NOT_COMPLETED': 'NOT_COMPLETED',
    'CANCELLED': 'CANCELLED',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[CancelTokenItemResponseStatusEnum];
  @override
  final String wireName = 'CancelTokenItemResponseStatusEnum';

  @override
  Object serialize(
          Serializers serializers, CancelTokenItemResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CancelTokenItemResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CancelTokenItemResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$CancelTokenItemResponse extends CancelTokenItemResponse {
  @override
  final String? bookingId;
  @override
  final String? serviceName;
  @override
  final DateTime? startsAt;
  @override
  final int? durationMinutes;
  @override
  final CancelTokenItemResponseStatusEnum? status;
  @override
  final bool? cancellable;

  factory _$CancelTokenItemResponse(
          [void Function(CancelTokenItemResponseBuilder)? updates]) =>
      (CancelTokenItemResponseBuilder()..update(updates))._build();

  _$CancelTokenItemResponse._(
      {this.bookingId,
      this.serviceName,
      this.startsAt,
      this.durationMinutes,
      this.status,
      this.cancellable})
      : super._();
  @override
  CancelTokenItemResponse rebuild(
          void Function(CancelTokenItemResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CancelTokenItemResponseBuilder toBuilder() =>
      CancelTokenItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CancelTokenItemResponse &&
        bookingId == other.bookingId &&
        serviceName == other.serviceName &&
        startsAt == other.startsAt &&
        durationMinutes == other.durationMinutes &&
        status == other.status &&
        cancellable == other.cancellable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, durationMinutes.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, cancellable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CancelTokenItemResponse')
          ..add('bookingId', bookingId)
          ..add('serviceName', serviceName)
          ..add('startsAt', startsAt)
          ..add('durationMinutes', durationMinutes)
          ..add('status', status)
          ..add('cancellable', cancellable))
        .toString();
  }
}

class CancelTokenItemResponseBuilder
    implements
        Builder<CancelTokenItemResponse, CancelTokenItemResponseBuilder> {
  _$CancelTokenItemResponse? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  int? _durationMinutes;
  int? get durationMinutes => _$this._durationMinutes;
  set durationMinutes(int? durationMinutes) =>
      _$this._durationMinutes = durationMinutes;

  CancelTokenItemResponseStatusEnum? _status;
  CancelTokenItemResponseStatusEnum? get status => _$this._status;
  set status(CancelTokenItemResponseStatusEnum? status) =>
      _$this._status = status;

  bool? _cancellable;
  bool? get cancellable => _$this._cancellable;
  set cancellable(bool? cancellable) => _$this._cancellable = cancellable;

  CancelTokenItemResponseBuilder() {
    CancelTokenItemResponse._defaults(this);
  }

  CancelTokenItemResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _serviceName = $v.serviceName;
      _startsAt = $v.startsAt;
      _durationMinutes = $v.durationMinutes;
      _status = $v.status;
      _cancellable = $v.cancellable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CancelTokenItemResponse other) {
    _$v = other as _$CancelTokenItemResponse;
  }

  @override
  void update(void Function(CancelTokenItemResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CancelTokenItemResponse build() => _build();

  _$CancelTokenItemResponse _build() {
    final _$result = _$v ??
        _$CancelTokenItemResponse._(
          bookingId: bookingId,
          serviceName: serviceName,
          startsAt: startsAt,
          durationMinutes: durationMinutes,
          status: status,
          cancellable: cancellable,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
