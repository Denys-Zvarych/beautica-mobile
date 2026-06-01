// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'approved_category_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApprovedCategoryResponse extends ApprovedCategoryResponse {
  @override
  final String? name;
  @override
  final String? displayName;

  factory _$ApprovedCategoryResponse(
          [void Function(ApprovedCategoryResponseBuilder)? updates]) =>
      (ApprovedCategoryResponseBuilder()..update(updates))._build();

  _$ApprovedCategoryResponse._({this.name, this.displayName}) : super._();
  @override
  ApprovedCategoryResponse rebuild(
          void Function(ApprovedCategoryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApprovedCategoryResponseBuilder toBuilder() =>
      ApprovedCategoryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApprovedCategoryResponse &&
        name == other.name &&
        displayName == other.displayName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApprovedCategoryResponse')
          ..add('name', name)
          ..add('displayName', displayName))
        .toString();
  }
}

class ApprovedCategoryResponseBuilder
    implements
        Builder<ApprovedCategoryResponse, ApprovedCategoryResponseBuilder> {
  _$ApprovedCategoryResponse? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  ApprovedCategoryResponseBuilder() {
    ApprovedCategoryResponse._defaults(this);
  }

  ApprovedCategoryResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _displayName = $v.displayName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApprovedCategoryResponse other) {
    _$v = other as _$ApprovedCategoryResponse;
  }

  @override
  void update(void Function(ApprovedCategoryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApprovedCategoryResponse build() => _build();

  _$ApprovedCategoryResponse _build() {
    final _$result = _$v ??
        _$ApprovedCategoryResponse._(
          name: name,
          displayName: displayName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
