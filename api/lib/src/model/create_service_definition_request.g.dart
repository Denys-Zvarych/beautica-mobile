// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_service_definition_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CreateServiceDefinitionRequestPriceTypeEnum
    _$createServiceDefinitionRequestPriceTypeEnum_FIXED =
    const CreateServiceDefinitionRequestPriceTypeEnum._('FIXED');
const CreateServiceDefinitionRequestPriceTypeEnum
    _$createServiceDefinitionRequestPriceTypeEnum_RANGE =
    const CreateServiceDefinitionRequestPriceTypeEnum._('RANGE');

CreateServiceDefinitionRequestPriceTypeEnum
    _$createServiceDefinitionRequestPriceTypeEnumValueOf(String name) {
  switch (name) {
    case 'FIXED':
      return _$createServiceDefinitionRequestPriceTypeEnum_FIXED;
    case 'RANGE':
      return _$createServiceDefinitionRequestPriceTypeEnum_RANGE;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CreateServiceDefinitionRequestPriceTypeEnum>
    _$createServiceDefinitionRequestPriceTypeEnumValues = BuiltSet<
        CreateServiceDefinitionRequestPriceTypeEnum>(const <CreateServiceDefinitionRequestPriceTypeEnum>[
  _$createServiceDefinitionRequestPriceTypeEnum_FIXED,
  _$createServiceDefinitionRequestPriceTypeEnum_RANGE,
]);

Serializer<CreateServiceDefinitionRequestPriceTypeEnum>
    _$createServiceDefinitionRequestPriceTypeEnumSerializer =
    _$CreateServiceDefinitionRequestPriceTypeEnumSerializer();

class _$CreateServiceDefinitionRequestPriceTypeEnumSerializer
    implements
        PrimitiveSerializer<CreateServiceDefinitionRequestPriceTypeEnum> {
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
    CreateServiceDefinitionRequestPriceTypeEnum
  ];
  @override
  final String wireName = 'CreateServiceDefinitionRequestPriceTypeEnum';

  @override
  Object serialize(Serializers serializers,
          CreateServiceDefinitionRequestPriceTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CreateServiceDefinitionRequestPriceTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CreateServiceDefinitionRequestPriceTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$CreateServiceDefinitionRequest extends CreateServiceDefinitionRequest {
  @override
  final String? name;
  @override
  final String? description;
  @override
  final String category;
  @override
  final int baseDurationMinutes;
  @override
  final int? bufferMinutesAfter;
  @override
  final CreateServiceDefinitionRequestPriceTypeEnum priceType;
  @override
  final num? price;
  @override
  final num? priceMin;
  @override
  final num? priceMax;
  @override
  final String? serviceTypeId;

  factory _$CreateServiceDefinitionRequest(
          [void Function(CreateServiceDefinitionRequestBuilder)? updates]) =>
      (CreateServiceDefinitionRequestBuilder()..update(updates))._build();

  _$CreateServiceDefinitionRequest._(
      {this.name,
      this.description,
      required this.category,
      required this.baseDurationMinutes,
      this.bufferMinutesAfter,
      required this.priceType,
      this.price,
      this.priceMin,
      this.priceMax,
      this.serviceTypeId})
      : super._();
  @override
  CreateServiceDefinitionRequest rebuild(
          void Function(CreateServiceDefinitionRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateServiceDefinitionRequestBuilder toBuilder() =>
      CreateServiceDefinitionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateServiceDefinitionRequest &&
        name == other.name &&
        description == other.description &&
        category == other.category &&
        baseDurationMinutes == other.baseDurationMinutes &&
        bufferMinutesAfter == other.bufferMinutesAfter &&
        priceType == other.priceType &&
        price == other.price &&
        priceMin == other.priceMin &&
        priceMax == other.priceMax &&
        serviceTypeId == other.serviceTypeId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, baseDurationMinutes.hashCode);
    _$hash = $jc(_$hash, bufferMinutesAfter.hashCode);
    _$hash = $jc(_$hash, priceType.hashCode);
    _$hash = $jc(_$hash, price.hashCode);
    _$hash = $jc(_$hash, priceMin.hashCode);
    _$hash = $jc(_$hash, priceMax.hashCode);
    _$hash = $jc(_$hash, serviceTypeId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateServiceDefinitionRequest')
          ..add('name', name)
          ..add('description', description)
          ..add('category', category)
          ..add('baseDurationMinutes', baseDurationMinutes)
          ..add('bufferMinutesAfter', bufferMinutesAfter)
          ..add('priceType', priceType)
          ..add('price', price)
          ..add('priceMin', priceMin)
          ..add('priceMax', priceMax)
          ..add('serviceTypeId', serviceTypeId))
        .toString();
  }
}

class CreateServiceDefinitionRequestBuilder
    implements
        Builder<CreateServiceDefinitionRequest,
            CreateServiceDefinitionRequestBuilder> {
  _$CreateServiceDefinitionRequest? _$v;

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

  CreateServiceDefinitionRequestPriceTypeEnum? _priceType;
  CreateServiceDefinitionRequestPriceTypeEnum? get priceType =>
      _$this._priceType;
  set priceType(CreateServiceDefinitionRequestPriceTypeEnum? priceType) =>
      _$this._priceType = priceType;

  num? _price;
  num? get price => _$this._price;
  set price(num? price) => _$this._price = price;

  num? _priceMin;
  num? get priceMin => _$this._priceMin;
  set priceMin(num? priceMin) => _$this._priceMin = priceMin;

  num? _priceMax;
  num? get priceMax => _$this._priceMax;
  set priceMax(num? priceMax) => _$this._priceMax = priceMax;

  String? _serviceTypeId;
  String? get serviceTypeId => _$this._serviceTypeId;
  set serviceTypeId(String? serviceTypeId) =>
      _$this._serviceTypeId = serviceTypeId;

  CreateServiceDefinitionRequestBuilder() {
    CreateServiceDefinitionRequest._defaults(this);
  }

  CreateServiceDefinitionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _description = $v.description;
      _category = $v.category;
      _baseDurationMinutes = $v.baseDurationMinutes;
      _bufferMinutesAfter = $v.bufferMinutesAfter;
      _priceType = $v.priceType;
      _price = $v.price;
      _priceMin = $v.priceMin;
      _priceMax = $v.priceMax;
      _serviceTypeId = $v.serviceTypeId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateServiceDefinitionRequest other) {
    _$v = other as _$CreateServiceDefinitionRequest;
  }

  @override
  void update(void Function(CreateServiceDefinitionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateServiceDefinitionRequest build() => _build();

  _$CreateServiceDefinitionRequest _build() {
    final _$result = _$v ??
        _$CreateServiceDefinitionRequest._(
          name: name,
          description: description,
          category: BuiltValueNullFieldError.checkNotNull(
              category, r'CreateServiceDefinitionRequest', 'category'),
          baseDurationMinutes: BuiltValueNullFieldError.checkNotNull(
              baseDurationMinutes,
              r'CreateServiceDefinitionRequest',
              'baseDurationMinutes'),
          bufferMinutesAfter: bufferMinutesAfter,
          priceType: BuiltValueNullFieldError.checkNotNull(
              priceType, r'CreateServiceDefinitionRequest', 'priceType'),
          price: price,
          priceMin: priceMin,
          priceMax: priceMax,
          serviceTypeId: serviceTypeId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
