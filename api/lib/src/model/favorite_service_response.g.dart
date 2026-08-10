// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_service_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const FavoriteServiceResponseSourceTypeEnum
    _$favoriteServiceResponseSourceTypeEnum_MASTER =
    const FavoriteServiceResponseSourceTypeEnum._('MASTER');
const FavoriteServiceResponseSourceTypeEnum
    _$favoriteServiceResponseSourceTypeEnum_SALON =
    const FavoriteServiceResponseSourceTypeEnum._('SALON');

FavoriteServiceResponseSourceTypeEnum
    _$favoriteServiceResponseSourceTypeEnumValueOf(String name) {
  switch (name) {
    case 'MASTER':
      return _$favoriteServiceResponseSourceTypeEnum_MASTER;
    case 'SALON':
      return _$favoriteServiceResponseSourceTypeEnum_SALON;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<FavoriteServiceResponseSourceTypeEnum>
    _$favoriteServiceResponseSourceTypeEnumValues = BuiltSet<
        FavoriteServiceResponseSourceTypeEnum>(const <FavoriteServiceResponseSourceTypeEnum>[
  _$favoriteServiceResponseSourceTypeEnum_MASTER,
  _$favoriteServiceResponseSourceTypeEnum_SALON,
]);

const FavoriteServiceResponsePriceTypeEnum
    _$favoriteServiceResponsePriceTypeEnum_FIXED =
    const FavoriteServiceResponsePriceTypeEnum._('FIXED');
const FavoriteServiceResponsePriceTypeEnum
    _$favoriteServiceResponsePriceTypeEnum_RANGE =
    const FavoriteServiceResponsePriceTypeEnum._('RANGE');

FavoriteServiceResponsePriceTypeEnum
    _$favoriteServiceResponsePriceTypeEnumValueOf(String name) {
  switch (name) {
    case 'FIXED':
      return _$favoriteServiceResponsePriceTypeEnum_FIXED;
    case 'RANGE':
      return _$favoriteServiceResponsePriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<FavoriteServiceResponsePriceTypeEnum>
    _$favoriteServiceResponsePriceTypeEnumValues = BuiltSet<
        FavoriteServiceResponsePriceTypeEnum>(const <FavoriteServiceResponsePriceTypeEnum>[
  _$favoriteServiceResponsePriceTypeEnum_FIXED,
  _$favoriteServiceResponsePriceTypeEnum_RANGE,
]);

Serializer<FavoriteServiceResponseSourceTypeEnum>
    _$favoriteServiceResponseSourceTypeEnumSerializer =
    _$FavoriteServiceResponseSourceTypeEnumSerializer();
Serializer<FavoriteServiceResponsePriceTypeEnum>
    _$favoriteServiceResponsePriceTypeEnumSerializer =
    _$FavoriteServiceResponsePriceTypeEnumSerializer();

class _$FavoriteServiceResponseSourceTypeEnumSerializer
    implements PrimitiveSerializer<FavoriteServiceResponseSourceTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
  };

  @override
  final Iterable<Type> types = const <Type>[
    FavoriteServiceResponseSourceTypeEnum
  ];
  @override
  final String wireName = 'FavoriteServiceResponseSourceTypeEnum';

  @override
  Object serialize(
          Serializers serializers, FavoriteServiceResponseSourceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  FavoriteServiceResponseSourceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      FavoriteServiceResponseSourceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$FavoriteServiceResponsePriceTypeEnumSerializer
    implements PrimitiveSerializer<FavoriteServiceResponsePriceTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'FIXED': 'FIXED',
    'RANGE': 'RANGE',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'FIXED': 'FIXED',
    'RANGE': 'RANGE',
  };

  @override
  final Iterable<Type> types = const <Type>[
    FavoriteServiceResponsePriceTypeEnum
  ];
  @override
  final String wireName = 'FavoriteServiceResponsePriceTypeEnum';

  @override
  Object serialize(
          Serializers serializers, FavoriteServiceResponsePriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  FavoriteServiceResponsePriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      FavoriteServiceResponsePriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$FavoriteServiceResponse extends FavoriteServiceResponse {
  @override
  final FavoriteServiceResponseSourceTypeEnum? sourceType;
  @override
  final String? masterServiceId;
  @override
  final String? masterId;
  @override
  final String? serviceDefId;
  @override
  final String? serviceName;
  @override
  final String? masterFirstName;
  @override
  final String? masterLastName;
  @override
  final String? masterAvatarUrl;
  @override
  final int? durationMinutes;
  @override
  final FavoriteServiceResponsePriceTypeEnum? priceType;
  @override
  final num? priceMin;
  @override
  final num? priceMax;
  @override
  final String? priceDisplay;
  @override
  final String? salonId;
  @override
  final String? salonName;
  @override
  final String? salonAvatarUrl;

  factory _$FavoriteServiceResponse(
          [void Function(FavoriteServiceResponseBuilder)? updates]) =>
      (FavoriteServiceResponseBuilder()..update(updates))._build();

  _$FavoriteServiceResponse._(
      {this.sourceType,
      this.masterServiceId,
      this.masterId,
      this.serviceDefId,
      this.serviceName,
      this.masterFirstName,
      this.masterLastName,
      this.masterAvatarUrl,
      this.durationMinutes,
      this.priceType,
      this.priceMin,
      this.priceMax,
      this.priceDisplay,
      this.salonId,
      this.salonName,
      this.salonAvatarUrl})
      : super._();
  @override
  FavoriteServiceResponse rebuild(
          void Function(FavoriteServiceResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FavoriteServiceResponseBuilder toBuilder() =>
      FavoriteServiceResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FavoriteServiceResponse &&
        sourceType == other.sourceType &&
        masterServiceId == other.masterServiceId &&
        masterId == other.masterId &&
        serviceDefId == other.serviceDefId &&
        serviceName == other.serviceName &&
        masterFirstName == other.masterFirstName &&
        masterLastName == other.masterLastName &&
        masterAvatarUrl == other.masterAvatarUrl &&
        durationMinutes == other.durationMinutes &&
        priceType == other.priceType &&
        priceMin == other.priceMin &&
        priceMax == other.priceMax &&
        priceDisplay == other.priceDisplay &&
        salonId == other.salonId &&
        salonName == other.salonName &&
        salonAvatarUrl == other.salonAvatarUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sourceType.hashCode);
    _$hash = $jc(_$hash, masterServiceId.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, serviceDefId.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, masterFirstName.hashCode);
    _$hash = $jc(_$hash, masterLastName.hashCode);
    _$hash = $jc(_$hash, masterAvatarUrl.hashCode);
    _$hash = $jc(_$hash, durationMinutes.hashCode);
    _$hash = $jc(_$hash, priceType.hashCode);
    _$hash = $jc(_$hash, priceMin.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jc(_$hash, priceDisplay.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, salonName.hashCode);
    _$hash = $jc(_$hash, salonAvatarUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FavoriteServiceResponse')
          ..add('sourceType', sourceType)
          ..add('masterServiceId', masterServiceId)
          ..add('masterId', masterId)
          ..add('serviceDefId', serviceDefId)
          ..add('serviceName', serviceName)
          ..add('masterFirstName', masterFirstName)
          ..add('masterLastName', masterLastName)
          ..add('masterAvatarUrl', masterAvatarUrl)
          ..add('durationMinutes', durationMinutes)
          ..add('priceType', priceType)
          ..add('priceMin', priceMin)
          ..add('priceMax', priceMax)
          ..add('priceDisplay', priceDisplay)
          ..add('salonId', salonId)
          ..add('salonName', salonName)
          ..add('salonAvatarUrl', salonAvatarUrl))
        .toString();
  }
}

class FavoriteServiceResponseBuilder
    implements
        Builder<FavoriteServiceResponse, FavoriteServiceResponseBuilder> {
  _$FavoriteServiceResponse? _$v;

  FavoriteServiceResponseSourceTypeEnum? _sourceType;
  FavoriteServiceResponseSourceTypeEnum? get sourceType => _$this._sourceType;
  set sourceType(FavoriteServiceResponseSourceTypeEnum? sourceType) =>
      _$this._sourceType = sourceType;

  String? _masterServiceId;
  String? get masterServiceId => _$this._masterServiceId;
  set masterServiceId(String? masterServiceId) =>
      _$this._masterServiceId = masterServiceId;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _serviceDefId;
  String? get serviceDefId => _$this._serviceDefId;
  set serviceDefId(String? serviceDefId) => _$this._serviceDefId = serviceDefId;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  String? _masterFirstName;
  String? get masterFirstName => _$this._masterFirstName;
  set masterFirstName(String? masterFirstName) =>
      _$this._masterFirstName = masterFirstName;

  String? _masterLastName;
  String? get masterLastName => _$this._masterLastName;
  set masterLastName(String? masterLastName) =>
      _$this._masterLastName = masterLastName;

  String? _masterAvatarUrl;
  String? get masterAvatarUrl => _$this._masterAvatarUrl;
  set masterAvatarUrl(String? masterAvatarUrl) =>
      _$this._masterAvatarUrl = masterAvatarUrl;

  int? _durationMinutes;
  int? get durationMinutes => _$this._durationMinutes;
  set durationMinutes(int? durationMinutes) =>
      _$this._durationMinutes = durationMinutes;

  FavoriteServiceResponsePriceTypeEnum? _priceType;
  FavoriteServiceResponsePriceTypeEnum? get priceType => _$this._priceType;
  set priceType(FavoriteServiceResponsePriceTypeEnum? priceType) =>
      _$this._priceType = priceType;

  num? _priceMin;
  num? get priceMin => _$this._priceMin;
  set priceMin(num? priceMin) => _$this._priceMin = priceMin;

  num? _priceMax;
  num? get priceMax => _$this._priceMax;
  set priceMax(num? priceMax) => _$this._priceMax = priceMax;

  String? _priceDisplay;
  String? get priceDisplay => _$this._priceDisplay;
  set priceDisplay(String? priceDisplay) => _$this._priceDisplay = priceDisplay;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  String? _salonName;
  String? get salonName => _$this._salonName;
  set salonName(String? salonName) => _$this._salonName = salonName;

  String? _salonAvatarUrl;
  String? get salonAvatarUrl => _$this._salonAvatarUrl;
  set salonAvatarUrl(String? salonAvatarUrl) =>
      _$this._salonAvatarUrl = salonAvatarUrl;

  FavoriteServiceResponseBuilder() {
    FavoriteServiceResponse._defaults(this);
  }

  FavoriteServiceResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sourceType = $v.sourceType;
      _masterServiceId = $v.masterServiceId;
      _masterId = $v.masterId;
      _serviceDefId = $v.serviceDefId;
      _serviceName = $v.serviceName;
      _masterFirstName = $v.masterFirstName;
      _masterLastName = $v.masterLastName;
      _masterAvatarUrl = $v.masterAvatarUrl;
      _durationMinutes = $v.durationMinutes;
      _priceType = $v.priceType;
      _priceMin = $v.priceMin;
      _priceMax = $v.priceMax;
      _priceDisplay = $v.priceDisplay;
      _salonId = $v.salonId;
      _salonName = $v.salonName;
      _salonAvatarUrl = $v.salonAvatarUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FavoriteServiceResponse other) {
    _$v = other as _$FavoriteServiceResponse;
  }

  @override
  void update(void Function(FavoriteServiceResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FavoriteServiceResponse build() => _build();

  _$FavoriteServiceResponse _build() {
    final _$result = _$v ??
        _$FavoriteServiceResponse._(
          sourceType: sourceType,
          masterServiceId: masterServiceId,
          masterId: masterId,
          serviceDefId: serviceDefId,
          serviceName: serviceName,
          masterFirstName: masterFirstName,
          masterLastName: masterLastName,
          masterAvatarUrl: masterAvatarUrl,
          durationMinutes: durationMinutes,
          priceType: priceType,
          priceMin: priceMin,
          priceMax: priceMax,
          priceDisplay: priceDisplay,
          salonId: salonId,
          salonName: salonName,
          salonAvatarUrl: salonAvatarUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
