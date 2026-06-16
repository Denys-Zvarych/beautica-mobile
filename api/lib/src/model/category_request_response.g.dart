// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_request_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CategoryRequestResponse extends CategoryRequestResponse {
  @override
  final String? name;
  @override
  final String? displayName;
  @override
  final String? status;

  factory _$CategoryRequestResponse(
          [void Function(CategoryRequestResponseBuilder)? updates]) =>
      (CategoryRequestResponseBuilder()..update(updates))._build();

  _$CategoryRequestResponse._({this.name, this.displayName, this.status})
      : super._();
  @override
  CategoryRequestResponse rebuild(
          void Function(CategoryRequestResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CategoryRequestResponseBuilder toBuilder() =>
      CategoryRequestResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CategoryRequestResponse &&
        name == other.name &&
        displayName == other.displayName &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CategoryRequestResponse')
          ..add('name', name)
          ..add('displayName', displayName)
          ..add('status', status))
        .toString();
  }
}

class CategoryRequestResponseBuilder
    implements
        Builder<CategoryRequestResponse, CategoryRequestResponseBuilder> {
  _$CategoryRequestResponse? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _status;
  String? get status => _$this._status;
  set status(String? status) => _$this._status = status;

  CategoryRequestResponseBuilder() {
    CategoryRequestResponse._defaults(this);
  }

  CategoryRequestResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _displayName = $v.displayName;
      _status = $v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CategoryRequestResponse other) {
    _$v = other as _$CategoryRequestResponse;
  }

  @override
  void update(void Function(CategoryRequestResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CategoryRequestResponse build() => _build();

  _$CategoryRequestResponse _build() {
    final _$result = _$v ??
        _$CategoryRequestResponse._(
          name: name,
          displayName: displayName,
          status: status,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
