// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'platform_category_usage_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlatformCategoryUsageResponse extends PlatformCategoryUsageResponse {
  @override
  final String? name;
  @override
  final bool? active;
  @override
  final int? usageCount;

  factory _$PlatformCategoryUsageResponse(
          [void Function(PlatformCategoryUsageResponseBuilder)? updates]) =>
      (PlatformCategoryUsageResponseBuilder()..update(updates))._build();

  _$PlatformCategoryUsageResponse._({this.name, this.active, this.usageCount})
      : super._();
  @override
  PlatformCategoryUsageResponse rebuild(
          void Function(PlatformCategoryUsageResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlatformCategoryUsageResponseBuilder toBuilder() =>
      PlatformCategoryUsageResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlatformCategoryUsageResponse &&
        name == other.name &&
        active == other.active &&
        usageCount == other.usageCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, active.hashCode);
    _$hash = $jc(_$hash, usageCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlatformCategoryUsageResponse')
          ..add('name', name)
          ..add('active', active)
          ..add('usageCount', usageCount))
        .toString();
  }
}

class PlatformCategoryUsageResponseBuilder
    implements
        Builder<PlatformCategoryUsageResponse,
            PlatformCategoryUsageResponseBuilder> {
  _$PlatformCategoryUsageResponse? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  bool? _active;
  bool? get active => _$this._active;
  set active(bool? active) => _$this._active = active;

  int? _usageCount;
  int? get usageCount => _$this._usageCount;
  set usageCount(int? usageCount) => _$this._usageCount = usageCount;

  PlatformCategoryUsageResponseBuilder() {
    PlatformCategoryUsageResponse._defaults(this);
  }

  PlatformCategoryUsageResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _active = $v.active;
      _usageCount = $v.usageCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlatformCategoryUsageResponse other) {
    _$v = other as _$PlatformCategoryUsageResponse;
  }

  @override
  void update(void Function(PlatformCategoryUsageResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlatformCategoryUsageResponse build() => _build();

  _$PlatformCategoryUsageResponse _build() {
    final _$result = _$v ??
        _$PlatformCategoryUsageResponse._(
          name: name,
          active: active,
          usageCount: usageCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
