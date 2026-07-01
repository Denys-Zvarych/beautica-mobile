// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_service_category_group.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonServiceCategoryGroup extends SalonServiceCategoryGroup {
  @override
  final String? category;
  @override
  final int? count;
  @override
  final BuiltList<ServiceDefinitionResponse>? services;

  factory _$SalonServiceCategoryGroup(
          [void Function(SalonServiceCategoryGroupBuilder)? updates]) =>
      (SalonServiceCategoryGroupBuilder()..update(updates))._build();

  _$SalonServiceCategoryGroup._({this.category, this.count, this.services})
      : super._();
  @override
  SalonServiceCategoryGroup rebuild(
          void Function(SalonServiceCategoryGroupBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonServiceCategoryGroupBuilder toBuilder() =>
      SalonServiceCategoryGroupBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonServiceCategoryGroup &&
        category == other.category &&
        count == other.count &&
        services == other.services;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jc(_$hash, services.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonServiceCategoryGroup')
          ..add('category', category)
          ..add('count', count)
          ..add('services', services))
        .toString();
  }
}

class SalonServiceCategoryGroupBuilder
    implements
        Builder<SalonServiceCategoryGroup, SalonServiceCategoryGroupBuilder> {
  _$SalonServiceCategoryGroup? _$v;

  String? _category;
  String? get category => _$this._category;
  set category(String? category) => _$this._category = category;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  ListBuilder<ServiceDefinitionResponse>? _services;
  ListBuilder<ServiceDefinitionResponse> get services =>
      _$this._services ??= ListBuilder<ServiceDefinitionResponse>();
  set services(ListBuilder<ServiceDefinitionResponse>? services) =>
      _$this._services = services;

  SalonServiceCategoryGroupBuilder() {
    SalonServiceCategoryGroup._defaults(this);
  }

  SalonServiceCategoryGroupBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _category = $v.category;
      _count = $v.count;
      _services = $v.services?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonServiceCategoryGroup other) {
    _$v = other as _$SalonServiceCategoryGroup;
  }

  @override
  void update(void Function(SalonServiceCategoryGroupBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonServiceCategoryGroup build() => _build();

  _$SalonServiceCategoryGroup _build() {
    _$SalonServiceCategoryGroup _$result;
    try {
      _$result = _$v ??
          _$SalonServiceCategoryGroup._(
            category: category,
            count: count,
            services: _services?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'services';
        _services?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonServiceCategoryGroup', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
