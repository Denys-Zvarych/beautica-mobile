// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_service_definition_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnum_MANICURE =
    const CreateServiceDefinitionRequestCategoryEnum._('MANICURE');
const CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnum_PEDICURE =
    const CreateServiceDefinitionRequestCategoryEnum._('PEDICURE');
const CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnum_EYELASH =
    const CreateServiceDefinitionRequestCategoryEnum._('EYELASH');
const CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnum_HAIRCUT =
    const CreateServiceDefinitionRequestCategoryEnum._('HAIRCUT');
const CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnum_MAKEUP =
    const CreateServiceDefinitionRequestCategoryEnum._('MAKEUP');
const CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnum_BROWS =
    const CreateServiceDefinitionRequestCategoryEnum._('BROWS');
const CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnum_OTHER =
    const CreateServiceDefinitionRequestCategoryEnum._('OTHER');

CreateServiceDefinitionRequestCategoryEnum
    _$createServiceDefinitionRequestCategoryEnumValueOf(String name) {
  switch (name) {
    case 'MANICURE':
      return _$createServiceDefinitionRequestCategoryEnum_MANICURE;
    case 'PEDICURE':
      return _$createServiceDefinitionRequestCategoryEnum_PEDICURE;
    case 'EYELASH':
      return _$createServiceDefinitionRequestCategoryEnum_EYELASH;
    case 'HAIRCUT':
      return _$createServiceDefinitionRequestCategoryEnum_HAIRCUT;
    case 'MAKEUP':
      return _$createServiceDefinitionRequestCategoryEnum_MAKEUP;
    case 'BROWS':
      return _$createServiceDefinitionRequestCategoryEnum_BROWS;
    case 'OTHER':
      return _$createServiceDefinitionRequestCategoryEnum_OTHER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CreateServiceDefinitionRequestCategoryEnum>
    _$createServiceDefinitionRequestCategoryEnumValues = BuiltSet<
        CreateServiceDefinitionRequestCategoryEnum>(const <CreateServiceDefinitionRequestCategoryEnum>[
  _$createServiceDefinitionRequestCategoryEnum_MANICURE,
  _$createServiceDefinitionRequestCategoryEnum_PEDICURE,
  _$createServiceDefinitionRequestCategoryEnum_EYELASH,
  _$createServiceDefinitionRequestCategoryEnum_HAIRCUT,
  _$createServiceDefinitionRequestCategoryEnum_MAKEUP,
  _$createServiceDefinitionRequestCategoryEnum_BROWS,
  _$createServiceDefinitionRequestCategoryEnum_OTHER,
]);

Serializer<CreateServiceDefinitionRequestCategoryEnum>
    _$createServiceDefinitionRequestCategoryEnumSerializer =
    _$CreateServiceDefinitionRequestCategoryEnumSerializer();

class _$CreateServiceDefinitionRequestCategoryEnumSerializer
    implements PrimitiveSerializer<CreateServiceDefinitionRequestCategoryEnum> {
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
    CreateServiceDefinitionRequestCategoryEnum
  ];
  @override
  final String wireName = 'CreateServiceDefinitionRequestCategoryEnum';

  @override
  Object serialize(Serializers serializers,
          CreateServiceDefinitionRequestCategoryEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CreateServiceDefinitionRequestCategoryEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CreateServiceDefinitionRequestCategoryEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$CreateServiceDefinitionRequest extends CreateServiceDefinitionRequest {
  @override
  final String name;
  @override
  final String? description;
  @override
  final CreateServiceDefinitionRequestCategoryEnum? category;
  @override
  final int baseDurationMinutes;
  @override
  final num basePrice;
  @override
  final int? bufferMinutesAfter;
  @override
  final String? serviceTypeId;

  factory _$CreateServiceDefinitionRequest(
          [void Function(CreateServiceDefinitionRequestBuilder)? updates]) =>
      (CreateServiceDefinitionRequestBuilder()..update(updates))._build();

  _$CreateServiceDefinitionRequest._(
      {required this.name,
      this.description,
      this.category,
      required this.baseDurationMinutes,
      required this.basePrice,
      this.bufferMinutesAfter,
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
        basePrice == other.basePrice &&
        bufferMinutesAfter == other.bufferMinutesAfter &&
        serviceTypeId == other.serviceTypeId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, baseDurationMinutes.hashCode);
    _$hash = $jc(_$hash, basePrice.hashCode);
    _$hash = $jc(_$hash, bufferMinutesAfter.hashCode);
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
          ..add('basePrice', basePrice)
          ..add('bufferMinutesAfter', bufferMinutesAfter)
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

  CreateServiceDefinitionRequestCategoryEnum? _category;
  CreateServiceDefinitionRequestCategoryEnum? get category => _$this._category;
  set category(CreateServiceDefinitionRequestCategoryEnum? category) =>
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
      _basePrice = $v.basePrice;
      _bufferMinutesAfter = $v.bufferMinutesAfter;
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
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CreateServiceDefinitionRequest', 'name'),
          description: description,
          category: category,
          baseDurationMinutes: BuiltValueNullFieldError.checkNotNull(
              baseDurationMinutes,
              r'CreateServiceDefinitionRequest',
              'baseDurationMinutes'),
          basePrice: BuiltValueNullFieldError.checkNotNull(
              basePrice, r'CreateServiceDefinitionRequest', 'basePrice'),
          bufferMinutesAfter: bufferMinutesAfter,
          serviceTypeId: serviceTypeId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
