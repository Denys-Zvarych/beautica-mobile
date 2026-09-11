// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_price_shape_mismatch_response_salon_price_max.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServicePriceShapeMismatchResponseSalonPriceMax
    extends ServicePriceShapeMismatchResponseSalonPriceMax {
  @override
  final AnyOf anyOf;

  factory _$ServicePriceShapeMismatchResponseSalonPriceMax(
          [void Function(ServicePriceShapeMismatchResponseSalonPriceMaxBuilder)?
              updates]) =>
      (ServicePriceShapeMismatchResponseSalonPriceMaxBuilder()..update(updates))
          ._build();

  _$ServicePriceShapeMismatchResponseSalonPriceMax._({required this.anyOf})
      : super._();
  @override
  ServicePriceShapeMismatchResponseSalonPriceMax rebuild(
          void Function(ServicePriceShapeMismatchResponseSalonPriceMaxBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServicePriceShapeMismatchResponseSalonPriceMaxBuilder toBuilder() =>
      ServicePriceShapeMismatchResponseSalonPriceMaxBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServicePriceShapeMismatchResponseSalonPriceMax &&
        anyOf == other.anyOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, anyOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
            r'ServicePriceShapeMismatchResponseSalonPriceMax')
          ..add('anyOf', anyOf))
        .toString();
  }
}

class ServicePriceShapeMismatchResponseSalonPriceMaxBuilder
    implements
        Builder<ServicePriceShapeMismatchResponseSalonPriceMax,
            ServicePriceShapeMismatchResponseSalonPriceMaxBuilder> {
  _$ServicePriceShapeMismatchResponseSalonPriceMax? _$v;

  AnyOf? _anyOf;
  AnyOf? get anyOf => _$this._anyOf;
  set anyOf(AnyOf? anyOf) => _$this._anyOf = anyOf;

  ServicePriceShapeMismatchResponseSalonPriceMaxBuilder() {
    ServicePriceShapeMismatchResponseSalonPriceMax._defaults(this);
  }

  ServicePriceShapeMismatchResponseSalonPriceMaxBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _anyOf = $v.anyOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServicePriceShapeMismatchResponseSalonPriceMax other) {
    _$v = other as _$ServicePriceShapeMismatchResponseSalonPriceMax;
  }

  @override
  void update(
      void Function(ServicePriceShapeMismatchResponseSalonPriceMaxBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ServicePriceShapeMismatchResponseSalonPriceMax build() => _build();

  _$ServicePriceShapeMismatchResponseSalonPriceMax _build() {
    final _$result = _$v ??
        _$ServicePriceShapeMismatchResponseSalonPriceMax._(
          anyOf: BuiltValueNullFieldError.checkNotNull(anyOf,
              r'ServicePriceShapeMismatchResponseSalonPriceMax', 'anyOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
