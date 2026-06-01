// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_platform_category_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreatePlatformCategoryRequest extends CreatePlatformCategoryRequest {
  @override
  final String name;

  factory _$CreatePlatformCategoryRequest(
          [void Function(CreatePlatformCategoryRequestBuilder)? updates]) =>
      (CreatePlatformCategoryRequestBuilder()..update(updates))._build();

  _$CreatePlatformCategoryRequest._({required this.name}) : super._();
  @override
  CreatePlatformCategoryRequest rebuild(
          void Function(CreatePlatformCategoryRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreatePlatformCategoryRequestBuilder toBuilder() =>
      CreatePlatformCategoryRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreatePlatformCategoryRequest && name == other.name;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreatePlatformCategoryRequest')
          ..add('name', name))
        .toString();
  }
}

class CreatePlatformCategoryRequestBuilder
    implements
        Builder<CreatePlatformCategoryRequest,
            CreatePlatformCategoryRequestBuilder> {
  _$CreatePlatformCategoryRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  CreatePlatformCategoryRequestBuilder() {
    CreatePlatformCategoryRequest._defaults(this);
  }

  CreatePlatformCategoryRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreatePlatformCategoryRequest other) {
    _$v = other as _$CreatePlatformCategoryRequest;
  }

  @override
  void update(void Function(CreatePlatformCategoryRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreatePlatformCategoryRequest build() => _build();

  _$CreatePlatformCategoryRequest _build() {
    final _$result = _$v ??
        _$CreatePlatformCategoryRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CreatePlatformCategoryRequest', 'name'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
