// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'platform_category_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlatformCategoryResponse extends PlatformCategoryResponse {
  @override
  final int? id;
  @override
  final String? name;
  @override
  final bool? active;

  factory _$PlatformCategoryResponse(
          [void Function(PlatformCategoryResponseBuilder)? updates]) =>
      (PlatformCategoryResponseBuilder()..update(updates))._build();

  _$PlatformCategoryResponse._({this.id, this.name, this.active}) : super._();
  @override
  PlatformCategoryResponse rebuild(
          void Function(PlatformCategoryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlatformCategoryResponseBuilder toBuilder() =>
      PlatformCategoryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlatformCategoryResponse &&
        id == other.id &&
        name == other.name &&
        active == other.active;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, active.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlatformCategoryResponse')
          ..add('id', id)
          ..add('name', name)
          ..add('active', active))
        .toString();
  }
}

class PlatformCategoryResponseBuilder
    implements
        Builder<PlatformCategoryResponse, PlatformCategoryResponseBuilder> {
  _$PlatformCategoryResponse? _$v;

  int? _id;
  int? get id => _$this._id;
  set id(int? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  bool? _active;
  bool? get active => _$this._active;
  set active(bool? active) => _$this._active = active;

  PlatformCategoryResponseBuilder() {
    PlatformCategoryResponse._defaults(this);
  }

  PlatformCategoryResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _active = $v.active;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlatformCategoryResponse other) {
    _$v = other as _$PlatformCategoryResponse;
  }

  @override
  void update(void Function(PlatformCategoryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlatformCategoryResponse build() => _build();

  _$PlatformCategoryResponse _build() {
    final _$result = _$v ??
        _$PlatformCategoryResponse._(
          id: id,
          name: name,
          active: active,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
