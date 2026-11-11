// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cancel_token_info_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CancelTokenInfoResponseStatusEnum
    _$cancelTokenInfoResponseStatusEnum_CONFIRMED =
    const CancelTokenInfoResponseStatusEnum._('CONFIRMED');
const CancelTokenInfoResponseStatusEnum
    _$cancelTokenInfoResponseStatusEnum_DECLINED =
    const CancelTokenInfoResponseStatusEnum._('DECLINED');
const CancelTokenInfoResponseStatusEnum
    _$cancelTokenInfoResponseStatusEnum_COMPLETED =
    const CancelTokenInfoResponseStatusEnum._('COMPLETED');
const CancelTokenInfoResponseStatusEnum
    _$cancelTokenInfoResponseStatusEnum_NOT_COMPLETED =
    const CancelTokenInfoResponseStatusEnum._('NOT_COMPLETED');
const CancelTokenInfoResponseStatusEnum
    _$cancelTokenInfoResponseStatusEnum_CANCELLED =
    const CancelTokenInfoResponseStatusEnum._('CANCELLED');
const CancelTokenInfoResponseStatusEnum
    _$cancelTokenInfoResponseStatusEnum_unknownDefaultOpenApi =
    const CancelTokenInfoResponseStatusEnum._('unknownDefaultOpenApi');

CancelTokenInfoResponseStatusEnum _$cancelTokenInfoResponseStatusEnumValueOf(
    String name) {
  switch (name) {
    case 'CONFIRMED':
      return _$cancelTokenInfoResponseStatusEnum_CONFIRMED;
    case 'DECLINED':
      return _$cancelTokenInfoResponseStatusEnum_DECLINED;
    case 'COMPLETED':
      return _$cancelTokenInfoResponseStatusEnum_COMPLETED;
    case 'NOT_COMPLETED':
      return _$cancelTokenInfoResponseStatusEnum_NOT_COMPLETED;
    case 'CANCELLED':
      return _$cancelTokenInfoResponseStatusEnum_CANCELLED;
    case 'unknownDefaultOpenApi':
      return _$cancelTokenInfoResponseStatusEnum_unknownDefaultOpenApi;
    default:
      return _$cancelTokenInfoResponseStatusEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<CancelTokenInfoResponseStatusEnum>
    _$cancelTokenInfoResponseStatusEnumValues = BuiltSet<
        CancelTokenInfoResponseStatusEnum>(const <CancelTokenInfoResponseStatusEnum>[
  _$cancelTokenInfoResponseStatusEnum_CONFIRMED,
  _$cancelTokenInfoResponseStatusEnum_DECLINED,
  _$cancelTokenInfoResponseStatusEnum_COMPLETED,
  _$cancelTokenInfoResponseStatusEnum_NOT_COMPLETED,
  _$cancelTokenInfoResponseStatusEnum_CANCELLED,
  _$cancelTokenInfoResponseStatusEnum_unknownDefaultOpenApi,
]);

Serializer<CancelTokenInfoResponseStatusEnum>
    _$cancelTokenInfoResponseStatusEnumSerializer =
    _$CancelTokenInfoResponseStatusEnumSerializer();

class _$CancelTokenInfoResponseStatusEnumSerializer
    implements PrimitiveSerializer<CancelTokenInfoResponseStatusEnum> {
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
  final Iterable<Type> types = const <Type>[CancelTokenInfoResponseStatusEnum];
  @override
  final String wireName = 'CancelTokenInfoResponseStatusEnum';

  @override
  Object serialize(
          Serializers serializers, CancelTokenInfoResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CancelTokenInfoResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CancelTokenInfoResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$CancelTokenInfoResponse extends CancelTokenInfoResponse {
  @override
  final String? masterName;
  @override
  final String? serviceName;
  @override
  final DateTime? startsAt;
  @override
  final bool? cancellable;
  @override
  final DateTime? windowClosesAt;
  @override
  final CancelTokenInfoResponseStatusEnum? status;
  @override
  final String? rebookPath;
  @override
  final String? salonName;
  @override
  final String? address;
  @override
  final String? locationNote;
  @override
  final BuiltList<CancelTokenItemResponse>? items;

  factory _$CancelTokenInfoResponse(
          [void Function(CancelTokenInfoResponseBuilder)? updates]) =>
      (CancelTokenInfoResponseBuilder()..update(updates))._build();

  _$CancelTokenInfoResponse._(
      {this.masterName,
      this.serviceName,
      this.startsAt,
      this.cancellable,
      this.windowClosesAt,
      this.status,
      this.rebookPath,
      this.salonName,
      this.address,
      this.locationNote,
      this.items})
      : super._();
  @override
  CancelTokenInfoResponse rebuild(
          void Function(CancelTokenInfoResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CancelTokenInfoResponseBuilder toBuilder() =>
      CancelTokenInfoResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CancelTokenInfoResponse &&
        masterName == other.masterName &&
        serviceName == other.serviceName &&
        startsAt == other.startsAt &&
        cancellable == other.cancellable &&
        windowClosesAt == other.windowClosesAt &&
        status == other.status &&
        rebookPath == other.rebookPath &&
        salonName == other.salonName &&
        address == other.address &&
        locationNote == other.locationNote &&
        items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, cancellable.hashCode);
    _$hash = $jc(_$hash, windowClosesAt.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, rebookPath.hashCode);
    _$hash = $jc(_$hash, salonName.hashCode);
    _$hash = $jc(_$hash, address.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CancelTokenInfoResponse')
          ..add('masterName', masterName)
          ..add('serviceName', serviceName)
          ..add('startsAt', startsAt)
          ..add('cancellable', cancellable)
          ..add('windowClosesAt', windowClosesAt)
          ..add('status', status)
          ..add('rebookPath', rebookPath)
          ..add('salonName', salonName)
          ..add('address', address)
          ..add('locationNote', locationNote)
          ..add('items', items))
        .toString();
  }
}

class CancelTokenInfoResponseBuilder
    implements
        Builder<CancelTokenInfoResponse, CancelTokenInfoResponseBuilder> {
  _$CancelTokenInfoResponse? _$v;

  String? _masterName;
  String? get masterName => _$this._masterName;
  set masterName(String? masterName) => _$this._masterName = masterName;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  bool? _cancellable;
  bool? get cancellable => _$this._cancellable;
  set cancellable(bool? cancellable) => _$this._cancellable = cancellable;

  DateTime? _windowClosesAt;
  DateTime? get windowClosesAt => _$this._windowClosesAt;
  set windowClosesAt(DateTime? windowClosesAt) =>
      _$this._windowClosesAt = windowClosesAt;

  CancelTokenInfoResponseStatusEnum? _status;
  CancelTokenInfoResponseStatusEnum? get status => _$this._status;
  set status(CancelTokenInfoResponseStatusEnum? status) =>
      _$this._status = status;

  String? _rebookPath;
  String? get rebookPath => _$this._rebookPath;
  set rebookPath(String? rebookPath) => _$this._rebookPath = rebookPath;

  String? _salonName;
  String? get salonName => _$this._salonName;
  set salonName(String? salonName) => _$this._salonName = salonName;

  String? _address;
  String? get address => _$this._address;
  set address(String? address) => _$this._address = address;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  ListBuilder<CancelTokenItemResponse>? _items;
  ListBuilder<CancelTokenItemResponse> get items =>
      _$this._items ??= ListBuilder<CancelTokenItemResponse>();
  set items(ListBuilder<CancelTokenItemResponse>? items) =>
      _$this._items = items;

  CancelTokenInfoResponseBuilder() {
    CancelTokenInfoResponse._defaults(this);
  }

  CancelTokenInfoResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterName = $v.masterName;
      _serviceName = $v.serviceName;
      _startsAt = $v.startsAt;
      _cancellable = $v.cancellable;
      _windowClosesAt = $v.windowClosesAt;
      _status = $v.status;
      _rebookPath = $v.rebookPath;
      _salonName = $v.salonName;
      _address = $v.address;
      _locationNote = $v.locationNote;
      _items = $v.items?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CancelTokenInfoResponse other) {
    _$v = other as _$CancelTokenInfoResponse;
  }

  @override
  void update(void Function(CancelTokenInfoResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CancelTokenInfoResponse build() => _build();

  _$CancelTokenInfoResponse _build() {
    _$CancelTokenInfoResponse _$result;
    try {
      _$result = _$v ??
          _$CancelTokenInfoResponse._(
            masterName: masterName,
            serviceName: serviceName,
            startsAt: startsAt,
            cancellable: cancellable,
            windowClosesAt: windowClosesAt,
            status: status,
            rebookPath: rebookPath,
            salonName: salonName,
            address: address,
            locationNote: locationNote,
            items: _items?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        _items?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CancelTokenInfoResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
