// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_category_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FavoriteCategoryView extends FavoriteCategoryView {
  @override
  final String? code;
  @override
  final String? label;

  factory _$FavoriteCategoryView(
          [void Function(FavoriteCategoryViewBuilder)? updates]) =>
      (FavoriteCategoryViewBuilder()..update(updates))._build();

  _$FavoriteCategoryView._({this.code, this.label}) : super._();
  @override
  FavoriteCategoryView rebuild(
          void Function(FavoriteCategoryViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FavoriteCategoryViewBuilder toBuilder() =>
      FavoriteCategoryViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FavoriteCategoryView &&
        code == other.code &&
        label == other.label;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FavoriteCategoryView')
          ..add('code', code)
          ..add('label', label))
        .toString();
  }
}

class FavoriteCategoryViewBuilder
    implements Builder<FavoriteCategoryView, FavoriteCategoryViewBuilder> {
  _$FavoriteCategoryView? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  FavoriteCategoryViewBuilder() {
    FavoriteCategoryView._defaults(this);
  }

  FavoriteCategoryViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _label = $v.label;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FavoriteCategoryView other) {
    _$v = other as _$FavoriteCategoryView;
  }

  @override
  void update(void Function(FavoriteCategoryViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FavoriteCategoryView build() => _build();

  _$FavoriteCategoryView _build() {
    final _$result = _$v ??
        _$FavoriteCategoryView._(
          code: code,
          label: label,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
