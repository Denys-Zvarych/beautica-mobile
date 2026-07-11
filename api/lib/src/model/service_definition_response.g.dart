// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_definition_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ServiceDefinitionResponsePriceTypeEnum
    _$serviceDefinitionResponsePriceTypeEnum_FIXED =
    const ServiceDefinitionResponsePriceTypeEnum._('FIXED');
const ServiceDefinitionResponsePriceTypeEnum
    _$serviceDefinitionResponsePriceTypeEnum_RANGE =
    const ServiceDefinitionResponsePriceTypeEnum._('RANGE');

ServiceDefinitionResponsePriceTypeEnum
    _$serviceDefinitionResponsePriceTypeEnumValueOf(String name) {
  switch (name) {
    case 'FIXED':
      return _$serviceDefinitionResponsePriceTypeEnum_FIXED;
    case 'RANGE':
      return _$serviceDefinitionResponsePriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ServiceDefinitionResponsePriceTypeEnum>
    _$serviceDefinitionResponsePriceTypeEnumValues = BuiltSet<
        ServiceDefinitionResponsePriceTypeEnum>(const <ServiceDefinitionResponsePriceTypeEnum>[
  _$serviceDefinitionResponsePriceTypeEnum_FIXED,
  _$serviceDefinitionResponsePriceTypeEnum_RANGE,
]);

Serializer<ServiceDefinitionResponsePriceTypeEnum>
    _$serviceDefinitionResponsePriceTypeEnumSerializer =
    _$ServiceDefinitionResponsePriceTypeEnumSerializer();

class _$ServiceDefinitionResponsePriceTypeEnumSerializer
    implements PrimitiveSerializer<ServiceDefinitionResponsePriceTypeEnum> {
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
    ServiceDefinitionResponsePriceTypeEnum
  ];
  @override
  final String wireName = 'ServiceDefinitionResponsePriceTypeEnum';

  @override
  Object serialize(Serializers serializers,
          ServiceDefinitionResponsePriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ServiceDefinitionResponsePriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ServiceDefinitionResponsePriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ServiceDefinitionResponse extends ServiceDefinitionResponse {
  @override
  final String? id;
  @override
  final String? name;
  @override
  final String? description;
  @override
  final String? category;
  @override
  final int? baseDurationMinutes;
  @override
  final int? bufferMinutesAfter;
  @override
  final bool? isActive;
  @override
  final String? serviceTypeId;
  @override
  final String? serviceTypeNameUk;
  @override
  final String? serviceTypeSlug;
  @override
  final String? photoUrl;
  @override
  final ServiceDefinitionResponsePriceTypeEnum? priceType;
  @override
  final num? priceMin;
  @override
  final num? priceMax;
  @override
  final String? priceDisplay;

  factory _$ServiceDefinitionResponse(
          [void Function(ServiceDefinitionResponseBuilder)? updates]) =>
      (ServiceDefinitionResponseBuilder()..update(updates))._build();

  _$ServiceDefinitionResponse._(
      {this.id,
      this.name,
      this.description,
      this.category,
      this.baseDurationMinutes,
      this.bufferMinutesAfter,
      this.isActive,
      this.serviceTypeId,
      this.serviceTypeNameUk,
      this.serviceTypeSlug,
      this.photoUrl,
      this.priceType,
      this.priceMin,
      this.priceMax,
      this.priceDisplay})
      : super._();
  @override
  ServiceDefinitionResponse rebuild(
          void Function(ServiceDefinitionResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServiceDefinitionResponseBuilder toBuilder() =>
      ServiceDefinitionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServiceDefinitionResponse &&
        id == other.id &&
        name == other.name &&
        description == other.description &&
        category == other.category &&
        baseDurationMinutes == other.baseDurationMinutes &&
        bufferMinutesAfter == other.bufferMinutesAfter &&
        isActive == other.isActive &&
        serviceTypeId == other.serviceTypeId &&
        serviceTypeNameUk == other.serviceTypeNameUk &&
        serviceTypeSlug == other.serviceTypeSlug &&
        photoUrl == other.photoUrl &&
        priceType == other.priceType &&
        priceMin == other.priceMin &&
        priceMax == other.priceMax &&
        priceDisplay == other.priceDisplay;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, baseDurationMinutes.hashCode);
    _$hash = $jc(_$hash, bufferMinutesAfter.hashCode);
    _$hash = $jc(_$hash, isActive.hashCode);
    _$hash = $jc(_$hash, serviceTypeId.hashCode);
    _$hash = $jc(_$hash, serviceTypeNameUk.hashCode);
    _$hash = $jc(_$hash, serviceTypeSlug.hashCode);
    _$hash = $jc(_$hash, photoUrl.hashCode);
    _$hash = $jc(_$hash, priceType.hashCode);
    _$hash = $jc(_$hash, priceMin.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jc(_$hash, priceDisplay.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServiceDefinitionResponse')
          ..add('id', id)
          ..add('name', name)
          ..add('description', description)
          ..add('category', category)
          ..add('baseDurationMinutes', baseDurationMinutes)
          ..add('bufferMinutesAfter', bufferMinutesAfter)
          ..add('isActive', isActive)
          ..add('serviceTypeId', serviceTypeId)
          ..add('serviceTypeNameUk', serviceTypeNameUk)
          ..add('serviceTypeSlug', serviceTypeSlug)
          ..add('photoUrl', photoUrl)
          ..add('priceType', priceType)
          ..add('priceMin', priceMin)
          ..add('priceMax', priceMax)
          ..add('priceDisplay', priceDisplay))
        .toString();
  }
}

class ServiceDefinitionResponseBuilder
    implements
        Builder<ServiceDefinitionResponse, ServiceDefinitionResponseBuilder> {
  _$ServiceDefinitionResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _category;
  String? get category => _$this._category;
  set category(String? category) => _$this._category = category;

  int? _baseDurationMinutes;
  int? get baseDurationMinutes => _$this._baseDurationMinutes;
  set baseDurationMinutes(int? baseDurationMinutes) =>
      _$this._baseDurationMinutes = baseDurationMinutes;

  int? _bufferMinutesAfter;
  int? get bufferMinutesAfter => _$this._bufferMinutesAfter;
  set bufferMinutesAfter(int? bufferMinutesAfter) =>
      _$this._bufferMinutesAfter = bufferMinutesAfter;

  bool? _isActive;
  bool? get isActive => _$this._isActive;
  set isActive(bool? isActive) => _$this._isActive = isActive;

  String? _serviceTypeId;
  String? get serviceTypeId => _$this._serviceTypeId;
  set serviceTypeId(String? serviceTypeId) =>
      _$this._serviceTypeId = serviceTypeId;

  String? _serviceTypeNameUk;
  String? get serviceTypeNameUk => _$this._serviceTypeNameUk;
  set serviceTypeNameUk(String? serviceTypeNameUk) =>
      _$this._serviceTypeNameUk = serviceTypeNameUk;

  String? _serviceTypeSlug;
  String? get serviceTypeSlug => _$this._serviceTypeSlug;
  set serviceTypeSlug(String? serviceTypeSlug) =>
      _$this._serviceTypeSlug = serviceTypeSlug;

  String? _photoUrl;
  String? get photoUrl => _$this._photoUrl;
  set photoUrl(String? photoUrl) => _$this._photoUrl = photoUrl;

  ServiceDefinitionResponsePriceTypeEnum? _priceType;
  ServiceDefinitionResponsePriceTypeEnum? get priceType => _$this._priceType;
  set priceType(ServiceDefinitionResponsePriceTypeEnum? priceType) =>
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

  ServiceDefinitionResponseBuilder() {
    ServiceDefinitionResponse._defaults(this);
  }

  ServiceDefinitionResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _description = $v.description;
      _category = $v.category;
      _baseDurationMinutes = $v.baseDurationMinutes;
      _bufferMinutesAfter = $v.bufferMinutesAfter;
      _isActive = $v.isActive;
      _serviceTypeId = $v.serviceTypeId;
      _serviceTypeNameUk = $v.serviceTypeNameUk;
      _serviceTypeSlug = $v.serviceTypeSlug;
      _photoUrl = $v.photoUrl;
      _priceType = $v.priceType;
      _priceMin = $v.priceMin;
      _priceMax = $v.priceMax;
      _priceDisplay = $v.priceDisplay;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServiceDefinitionResponse other) {
    _$v = other as _$ServiceDefinitionResponse;
  }

  @override
  void update(void Function(ServiceDefinitionResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServiceDefinitionResponse build() => _build();

  _$ServiceDefinitionResponse _build() {
    final _$result = _$v ??
        _$ServiceDefinitionResponse._(
          id: id,
          name: name,
          description: description,
          category: category,
          baseDurationMinutes: baseDurationMinutes,
          bufferMinutesAfter: bufferMinutesAfter,
          isActive: isActive,
          serviceTypeId: serviceTypeId,
          serviceTypeNameUk: serviceTypeNameUk,
          serviceTypeSlug: serviceTypeSlug,
          photoUrl: photoUrl,
          priceType: priceType,
          priceMin: priceMin,
          priceMax: priceMax,
          priceDisplay: priceDisplay,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
