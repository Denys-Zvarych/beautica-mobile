// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_service_definition_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateServiceDefinitionRequest extends UpdateServiceDefinitionRequest {
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

  factory _$UpdateServiceDefinitionRequest(
          [void Function(UpdateServiceDefinitionRequestBuilder)? updates]) =>
      (UpdateServiceDefinitionRequestBuilder()..update(updates))._build();

  _$UpdateServiceDefinitionRequest._(
      {this.name,
      this.description,
      this.category,
      this.baseDurationMinutes,
      this.basePrice,
      this.bufferMinutesAfter})
      : super._();
  @override
  UpdateServiceDefinitionRequest rebuild(
          void Function(UpdateServiceDefinitionRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateServiceDefinitionRequestBuilder toBuilder() =>
      UpdateServiceDefinitionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateServiceDefinitionRequest &&
        name == other.name &&
        description == other.description &&
        category == other.category &&
        baseDurationMinutes == other.baseDurationMinutes &&
        basePrice == other.basePrice &&
        bufferMinutesAfter == other.bufferMinutesAfter;
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
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateServiceDefinitionRequest')
          ..add('name', name)
          ..add('description', description)
          ..add('category', category)
          ..add('baseDurationMinutes', baseDurationMinutes)
          ..add('basePrice', basePrice)
          ..add('bufferMinutesAfter', bufferMinutesAfter))
        .toString();
  }
}

class UpdateServiceDefinitionRequestBuilder
    implements
        Builder<UpdateServiceDefinitionRequest,
            UpdateServiceDefinitionRequestBuilder> {
  _$UpdateServiceDefinitionRequest? _$v;

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

  UpdateServiceDefinitionRequestBuilder() {
    UpdateServiceDefinitionRequest._defaults(this);
  }

  UpdateServiceDefinitionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _description = $v.description;
      _category = $v.category;
      _baseDurationMinutes = $v.baseDurationMinutes;
      _basePrice = $v.basePrice;
      _bufferMinutesAfter = $v.bufferMinutesAfter;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateServiceDefinitionRequest other) {
    _$v = other as _$UpdateServiceDefinitionRequest;
  }

  @override
  void update(void Function(UpdateServiceDefinitionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateServiceDefinitionRequest build() => _build();

  _$UpdateServiceDefinitionRequest _build() {
    final _$result = _$v ??
        _$UpdateServiceDefinitionRequest._(
          name: name,
          description: description,
          category: category,
          baseDurationMinutes: baseDurationMinutes,
          basePrice: basePrice,
          bufferMinutesAfter: bufferMinutesAfter,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
