// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_definition_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnum_MANICURE =
    const ServiceDefinitionResponseCategoryEnum._('MANICURE');
const ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnum_PEDICURE =
    const ServiceDefinitionResponseCategoryEnum._('PEDICURE');
const ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnum_EYELASH =
    const ServiceDefinitionResponseCategoryEnum._('EYELASH');
const ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnum_HAIRCUT =
    const ServiceDefinitionResponseCategoryEnum._('HAIRCUT');
const ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnum_MAKEUP =
    const ServiceDefinitionResponseCategoryEnum._('MAKEUP');
const ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnum_BROWS =
    const ServiceDefinitionResponseCategoryEnum._('BROWS');
const ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnum_OTHER =
    const ServiceDefinitionResponseCategoryEnum._('OTHER');

ServiceDefinitionResponseCategoryEnum
    _$serviceDefinitionResponseCategoryEnumValueOf(String name) {
  switch (name) {
    case 'MANICURE':
      return _$serviceDefinitionResponseCategoryEnum_MANICURE;
    case 'PEDICURE':
      return _$serviceDefinitionResponseCategoryEnum_PEDICURE;
    case 'EYELASH':
      return _$serviceDefinitionResponseCategoryEnum_EYELASH;
    case 'HAIRCUT':
      return _$serviceDefinitionResponseCategoryEnum_HAIRCUT;
    case 'MAKEUP':
      return _$serviceDefinitionResponseCategoryEnum_MAKEUP;
    case 'BROWS':
      return _$serviceDefinitionResponseCategoryEnum_BROWS;
    case 'OTHER':
      return _$serviceDefinitionResponseCategoryEnum_OTHER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ServiceDefinitionResponseCategoryEnum>
    _$serviceDefinitionResponseCategoryEnumValues = BuiltSet<
        ServiceDefinitionResponseCategoryEnum>(const <ServiceDefinitionResponseCategoryEnum>[
  _$serviceDefinitionResponseCategoryEnum_MANICURE,
  _$serviceDefinitionResponseCategoryEnum_PEDICURE,
  _$serviceDefinitionResponseCategoryEnum_EYELASH,
  _$serviceDefinitionResponseCategoryEnum_HAIRCUT,
  _$serviceDefinitionResponseCategoryEnum_MAKEUP,
  _$serviceDefinitionResponseCategoryEnum_BROWS,
  _$serviceDefinitionResponseCategoryEnum_OTHER,
]);

Serializer<ServiceDefinitionResponseCategoryEnum>
    _$serviceDefinitionResponseCategoryEnumSerializer =
    _$ServiceDefinitionResponseCategoryEnumSerializer();

class _$ServiceDefinitionResponseCategoryEnumSerializer
    implements PrimitiveSerializer<ServiceDefinitionResponseCategoryEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'MANICURE': 'MANICURE',
    'PEDICURE': 'PEDICURE',
    'EYELASH': 'EYELASH',
    'HAIRCUT': 'HAIRCUT',
    'MAKEUP': 'MAKEUP',
    'BROWS': 'BROWS',
    'OTHER': 'OTHER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'MANICURE': 'MANICURE',
    'PEDICURE': 'PEDICURE',
    'EYELASH': 'EYELASH',
    'HAIRCUT': 'HAIRCUT',
    'MAKEUP': 'MAKEUP',
    'BROWS': 'BROWS',
    'OTHER': 'OTHER',
  };

  @override
  final Iterable<Type> types = const <Type>[
    ServiceDefinitionResponseCategoryEnum
  ];
  @override
  final String wireName = 'ServiceDefinitionResponseCategoryEnum';

  @override
  Object serialize(
          Serializers serializers, ServiceDefinitionResponseCategoryEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ServiceDefinitionResponseCategoryEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ServiceDefinitionResponseCategoryEnum.valueOf(
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
  final ServiceDefinitionResponseCategoryEnum? category;
  @override
  final int? baseDurationMinutes;
  @override
  final num? basePrice;
  @override
  final int? bufferMinutesAfter;
  @override
  final bool? isActive;
  @override
  final String? serviceTypeId;
  @override
  final String? serviceTypeNameUk;

  factory _$ServiceDefinitionResponse(
          [void Function(ServiceDefinitionResponseBuilder)? updates]) =>
      (ServiceDefinitionResponseBuilder()..update(updates))._build();

  _$ServiceDefinitionResponse._(
      {this.id,
      this.name,
      this.description,
      this.category,
      this.baseDurationMinutes,
      this.basePrice,
      this.bufferMinutesAfter,
      this.isActive,
      this.serviceTypeId,
      this.serviceTypeNameUk})
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
        basePrice == other.basePrice &&
        bufferMinutesAfter == other.bufferMinutesAfter &&
        isActive == other.isActive &&
        serviceTypeId == other.serviceTypeId &&
        serviceTypeNameUk == other.serviceTypeNameUk;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, baseDurationMinutes.hashCode);
    _$hash = $jc(_$hash, basePrice.hashCode);
    _$hash = $jc(_$hash, bufferMinutesAfter.hashCode);
    _$hash = $jc(_$hash, isActive.hashCode);
    _$hash = $jc(_$hash, serviceTypeId.hashCode);
    _$hash = $jc(_$hash, serviceTypeNameUk.hashCode);
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
          ..add('basePrice', basePrice)
          ..add('bufferMinutesAfter', bufferMinutesAfter)
          ..add('isActive', isActive)
          ..add('serviceTypeId', serviceTypeId)
          ..add('serviceTypeNameUk', serviceTypeNameUk))
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

  ServiceDefinitionResponseCategoryEnum? _category;
  ServiceDefinitionResponseCategoryEnum? get category => _$this._category;
  set category(ServiceDefinitionResponseCategoryEnum? category) =>
      _$this._category = category;

  int? _baseDurationMinutes;
  int? get baseDurationMinutes => _$this._baseDurationMinutes;
  set baseDurationMinutes(int? baseDurationMinutes) =>
      _$this._baseDurationMinutes = baseDurationMinutes;

  num? _basePrice;
  num? get basePrice => _$this._basePrice;
  set basePrice(num? basePrice) => _$this._basePrice = basePrice;

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
      _basePrice = $v.basePrice;
      _bufferMinutesAfter = $v.bufferMinutesAfter;
      _isActive = $v.isActive;
      _serviceTypeId = $v.serviceTypeId;
      _serviceTypeNameUk = $v.serviceTypeNameUk;
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
          basePrice: basePrice,
          bufferMinutesAfter: bufferMinutesAfter,
          isActive: isActive,
          serviceTypeId: serviceTypeId,
          serviceTypeNameUk: serviceTypeNameUk,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
