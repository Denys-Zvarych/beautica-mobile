// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_category_request_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateCategoryRequestRequest extends CreateCategoryRequestRequest {
  @override
  final String name;
  @override
  final String displayName;
  @override
  final String? initialServiceName;

  factory _$CreateCategoryRequestRequest(
          [void Function(CreateCategoryRequestRequestBuilder)? updates]) =>
      (CreateCategoryRequestRequestBuilder()..update(updates))._build();

  _$CreateCategoryRequestRequest._(
      {required this.name, required this.displayName, this.initialServiceName})
      : super._();
  @override
  CreateCategoryRequestRequest rebuild(
          void Function(CreateCategoryRequestRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateCategoryRequestRequestBuilder toBuilder() =>
      CreateCategoryRequestRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateCategoryRequestRequest &&
        name == other.name &&
        displayName == other.displayName &&
        initialServiceName == other.initialServiceName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, initialServiceName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateCategoryRequestRequest')
          ..add('name', name)
          ..add('displayName', displayName)
          ..add('initialServiceName', initialServiceName))
        .toString();
  }
}

class CreateCategoryRequestRequestBuilder
    implements
        Builder<CreateCategoryRequestRequest,
            CreateCategoryRequestRequestBuilder> {
  _$CreateCategoryRequestRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _initialServiceName;
  String? get initialServiceName => _$this._initialServiceName;
  set initialServiceName(String? initialServiceName) =>
      _$this._initialServiceName = initialServiceName;

  CreateCategoryRequestRequestBuilder() {
    CreateCategoryRequestRequest._defaults(this);
  }

  CreateCategoryRequestRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _displayName = $v.displayName;
      _initialServiceName = $v.initialServiceName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateCategoryRequestRequest other) {
    _$v = other as _$CreateCategoryRequestRequest;
  }

  @override
  void update(void Function(CreateCategoryRequestRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateCategoryRequestRequest build() => _build();

  _$CreateCategoryRequestRequest _build() {
    final _$result = _$v ??
        _$CreateCategoryRequestRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CreateCategoryRequestRequest', 'name'),
          displayName: BuiltValueNullFieldError.checkNotNull(
              displayName, r'CreateCategoryRequestRequest', 'displayName'),
          initialServiceName: initialServiceName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
