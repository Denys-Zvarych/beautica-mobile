// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_ref.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CategoryRef extends CategoryRef {
  @override
  final String id;
  @override
  final String name;
  @override
  final String key;

  factory _$CategoryRef([void Function(CategoryRefBuilder)? updates]) =>
      (CategoryRefBuilder()..update(updates))._build();

  _$CategoryRef._({required this.id, required this.name, required this.key})
      : super._();
  @override
  CategoryRef rebuild(void Function(CategoryRefBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CategoryRefBuilder toBuilder() => CategoryRefBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CategoryRef &&
        id == other.id &&
        name == other.name &&
        key == other.key;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CategoryRef')
          ..add('id', id)
          ..add('name', name)
          ..add('key', key))
        .toString();
  }
}

class CategoryRefBuilder implements Builder<CategoryRef, CategoryRefBuilder> {
  _$CategoryRef? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  CategoryRefBuilder() {
    CategoryRef._defaults(this);
  }

  CategoryRefBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _key = $v.key;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CategoryRef other) {
    _$v = other as _$CategoryRef;
  }

  @override
  void update(void Function(CategoryRefBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CategoryRef build() => _build();

  _$CategoryRef _build() {
    final _$result = _$v ??
        _$CategoryRef._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'CategoryRef', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CategoryRef', 'name'),
          key:
              BuiltValueNullFieldError.checkNotNull(key, r'CategoryRef', 'key'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
