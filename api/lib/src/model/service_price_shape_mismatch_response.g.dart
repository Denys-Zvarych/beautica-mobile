// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_price_shape_mismatch_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ServicePriceShapeMismatchResponseSalonPriceTypeEnum
    _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_FIXED =
    const ServicePriceShapeMismatchResponseSalonPriceTypeEnum._('FIXED');
const ServicePriceShapeMismatchResponseSalonPriceTypeEnum
    _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_RANGE =
    const ServicePriceShapeMismatchResponseSalonPriceTypeEnum._('RANGE');

ServicePriceShapeMismatchResponseSalonPriceTypeEnum
    _$servicePriceShapeMismatchResponseSalonPriceTypeEnumValueOf(String name) {
  switch (name) {
    case 'FIXED':
      return _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_FIXED;
    case 'RANGE':
      return _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ServicePriceShapeMismatchResponseSalonPriceTypeEnum>
    _$servicePriceShapeMismatchResponseSalonPriceTypeEnumValues = BuiltSet<
        ServicePriceShapeMismatchResponseSalonPriceTypeEnum>(const <ServicePriceShapeMismatchResponseSalonPriceTypeEnum>[
  _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_FIXED,
  _$servicePriceShapeMismatchResponseSalonPriceTypeEnum_RANGE,
]);

Serializer<ServicePriceShapeMismatchResponseSalonPriceTypeEnum>
    _$servicePriceShapeMismatchResponseSalonPriceTypeEnumSerializer =
    _$ServicePriceShapeMismatchResponseSalonPriceTypeEnumSerializer();

class _$ServicePriceShapeMismatchResponseSalonPriceTypeEnumSerializer
    implements
        PrimitiveSerializer<
            ServicePriceShapeMismatchResponseSalonPriceTypeEnum> {
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
    ServicePriceShapeMismatchResponseSalonPriceTypeEnum
  ];
  @override
  final String wireName = 'ServicePriceShapeMismatchResponseSalonPriceTypeEnum';

  @override
  Object serialize(Serializers serializers,
          ServicePriceShapeMismatchResponseSalonPriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ServicePriceShapeMismatchResponseSalonPriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ServicePriceShapeMismatchResponseSalonPriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ServicePriceShapeMismatchResponse
    extends ServicePriceShapeMismatchResponse {
  @override
  final String? code;
  @override
  final String? serviceName;
  @override
  final String? existingServiceDefId;
  @override
  final ServicePriceShapeMismatchResponseSalonPriceTypeEnum? salonPriceType;
  @override
  final ServicePriceShapeMismatchResponseSalonPriceMin? salonPriceMin;
  @override
  final ServicePriceShapeMismatchResponseSalonPriceMax? salonPriceMax;

  factory _$ServicePriceShapeMismatchResponse(
          [void Function(ServicePriceShapeMismatchResponseBuilder)? updates]) =>
      (ServicePriceShapeMismatchResponseBuilder()..update(updates))._build();

  _$ServicePriceShapeMismatchResponse._(
      {this.code,
      this.serviceName,
      this.existingServiceDefId,
      this.salonPriceType,
      this.salonPriceMin,
      this.salonPriceMax})
      : super._();
  @override
  ServicePriceShapeMismatchResponse rebuild(
          void Function(ServicePriceShapeMismatchResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServicePriceShapeMismatchResponseBuilder toBuilder() =>
      ServicePriceShapeMismatchResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServicePriceShapeMismatchResponse &&
        code == other.code &&
        serviceName == other.serviceName &&
        existingServiceDefId == other.existingServiceDefId &&
        salonPriceType == other.salonPriceType &&
        salonPriceMin == other.salonPriceMin &&
        salonPriceMax == other.salonPriceMax;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, existingServiceDefId.hashCode);
    _$hash = $jc(_$hash, salonPriceType.hashCode);
    _$hash = $jc(_$hash, salonPriceMin.hashCode);
    _$hash = $jc(_$hash, salonPriceMax.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServicePriceShapeMismatchResponse')
          ..add('code', code)
          ..add('serviceName', serviceName)
          ..add('existingServiceDefId', existingServiceDefId)
          ..add('salonPriceType', salonPriceType)
          ..add('salonPriceMin', salonPriceMin)
          ..add('salonPriceMax', salonPriceMax))
        .toString();
  }
}

class ServicePriceShapeMismatchResponseBuilder
    implements
        Builder<ServicePriceShapeMismatchResponse,
            ServicePriceShapeMismatchResponseBuilder> {
  _$ServicePriceShapeMismatchResponse? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  String? _existingServiceDefId;
  String? get existingServiceDefId => _$this._existingServiceDefId;
  set existingServiceDefId(String? existingServiceDefId) =>
      _$this._existingServiceDefId = existingServiceDefId;

  ServicePriceShapeMismatchResponseSalonPriceTypeEnum? _salonPriceType;
  ServicePriceShapeMismatchResponseSalonPriceTypeEnum? get salonPriceType =>
      _$this._salonPriceType;
  set salonPriceType(
          ServicePriceShapeMismatchResponseSalonPriceTypeEnum?
              salonPriceType) =>
      _$this._salonPriceType = salonPriceType;

  ServicePriceShapeMismatchResponseSalonPriceMinBuilder? _salonPriceMin;
  ServicePriceShapeMismatchResponseSalonPriceMinBuilder get salonPriceMin =>
      _$this._salonPriceMin ??=
          ServicePriceShapeMismatchResponseSalonPriceMinBuilder();
  set salonPriceMin(
          ServicePriceShapeMismatchResponseSalonPriceMinBuilder?
              salonPriceMin) =>
      _$this._salonPriceMin = salonPriceMin;

  ServicePriceShapeMismatchResponseSalonPriceMaxBuilder? _salonPriceMax;
  ServicePriceShapeMismatchResponseSalonPriceMaxBuilder get salonPriceMax =>
      _$this._salonPriceMax ??=
          ServicePriceShapeMismatchResponseSalonPriceMaxBuilder();
  set salonPriceMax(
          ServicePriceShapeMismatchResponseSalonPriceMaxBuilder?
              salonPriceMax) =>
      _$this._salonPriceMax = salonPriceMax;

  ServicePriceShapeMismatchResponseBuilder() {
    ServicePriceShapeMismatchResponse._defaults(this);
  }

  ServicePriceShapeMismatchResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _serviceName = $v.serviceName;
      _existingServiceDefId = $v.existingServiceDefId;
      _salonPriceType = $v.salonPriceType;
      _salonPriceMin = $v.salonPriceMin?.toBuilder();
      _salonPriceMax = $v.salonPriceMax?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServicePriceShapeMismatchResponse other) {
    _$v = other as _$ServicePriceShapeMismatchResponse;
  }

  @override
  void update(
      void Function(ServicePriceShapeMismatchResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServicePriceShapeMismatchResponse build() => _build();

  _$ServicePriceShapeMismatchResponse _build() {
    _$ServicePriceShapeMismatchResponse _$result;
    try {
      _$result = _$v ??
          _$ServicePriceShapeMismatchResponse._(
            code: code,
            serviceName: serviceName,
            existingServiceDefId: existingServiceDefId,
            salonPriceType: salonPriceType,
            salonPriceMin: _salonPriceMin?.build(),
            salonPriceMax: _salonPriceMax?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'salonPriceMin';
        _salonPriceMin?.build();
        _$failedField = 'salonPriceMax';
        _salonPriceMax?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ServicePriceShapeMismatchResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
