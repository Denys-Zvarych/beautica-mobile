// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_definition_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

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
  final num? basePrice;
  @override
  final int? bufferMinutesAfter;
  @override
  final bool? isActive;
  @override
  final String? serviceTypeId;
  @override
  final String? serviceTypeNameUk;
  @override
  final String? photoUrl;

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
      this.serviceTypeNameUk,
      this.photoUrl})
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
        serviceTypeNameUk == other.serviceTypeNameUk &&
        photoUrl == other.photoUrl;
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
    _$hash = $jc(_$hash, photoUrl.hashCode);
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
          ..add('serviceTypeNameUk', serviceTypeNameUk)
          ..add('photoUrl', photoUrl))
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

  String? _photoUrl;
  String? get photoUrl => _$this._photoUrl;
  set photoUrl(String? photoUrl) => _$this._photoUrl = photoUrl;

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
      _photoUrl = $v.photoUrl;
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
          photoUrl: photoUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
