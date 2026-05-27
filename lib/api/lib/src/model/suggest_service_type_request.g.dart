// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'suggest_service_type_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SuggestServiceTypeRequest extends SuggestServiceTypeRequest {
  @override
  final String name;
  @override
  final String categoryId;
  @override
  final String? description;

  factory _$SuggestServiceTypeRequest(
          [void Function(SuggestServiceTypeRequestBuilder)? updates]) =>
      (SuggestServiceTypeRequestBuilder()..update(updates))._build();

  _$SuggestServiceTypeRequest._(
      {required this.name, required this.categoryId, this.description})
      : super._();
  @override
  SuggestServiceTypeRequest rebuild(
          void Function(SuggestServiceTypeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SuggestServiceTypeRequestBuilder toBuilder() =>
      SuggestServiceTypeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SuggestServiceTypeRequest &&
        name == other.name &&
        categoryId == other.categoryId &&
        description == other.description;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SuggestServiceTypeRequest')
          ..add('name', name)
          ..add('categoryId', categoryId)
          ..add('description', description))
        .toString();
  }
}

class SuggestServiceTypeRequestBuilder
    implements
        Builder<SuggestServiceTypeRequest, SuggestServiceTypeRequestBuilder> {
  _$SuggestServiceTypeRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  SuggestServiceTypeRequestBuilder() {
    SuggestServiceTypeRequest._defaults(this);
  }

  SuggestServiceTypeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _categoryId = $v.categoryId;
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SuggestServiceTypeRequest other) {
    _$v = other as _$SuggestServiceTypeRequest;
  }

  @override
  void update(void Function(SuggestServiceTypeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SuggestServiceTypeRequest build() => _build();

  _$SuggestServiceTypeRequest _build() {
    final _$result = _$v ??
        _$SuggestServiceTypeRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'SuggestServiceTypeRequest', 'name'),
          categoryId: BuiltValueNullFieldError.checkNotNull(
              categoryId, r'SuggestServiceTypeRequest', 'categoryId'),
          description: description,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
