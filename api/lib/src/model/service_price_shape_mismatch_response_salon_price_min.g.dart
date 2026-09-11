// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_price_shape_mismatch_response_salon_price_min.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServicePriceShapeMismatchResponseSalonPriceMin
    extends ServicePriceShapeMismatchResponseSalonPriceMin {
  @override
  final AnyOf anyOf;

  factory _$ServicePriceShapeMismatchResponseSalonPriceMin(
          [void Function(ServicePriceShapeMismatchResponseSalonPriceMinBuilder)?
              updates]) =>
      (ServicePriceShapeMismatchResponseSalonPriceMinBuilder()..update(updates))
          ._build();

  _$ServicePriceShapeMismatchResponseSalonPriceMin._({required this.anyOf})
      : super._();
  @override
  ServicePriceShapeMismatchResponseSalonPriceMin rebuild(
          void Function(ServicePriceShapeMismatchResponseSalonPriceMinBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServicePriceShapeMismatchResponseSalonPriceMinBuilder toBuilder() =>
      ServicePriceShapeMismatchResponseSalonPriceMinBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServicePriceShapeMismatchResponseSalonPriceMin &&
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
            r'ServicePriceShapeMismatchResponseSalonPriceMin')
          ..add('anyOf', anyOf))
        .toString();
  }
}

class ServicePriceShapeMismatchResponseSalonPriceMinBuilder
    implements
        Builder<ServicePriceShapeMismatchResponseSalonPriceMin,
            ServicePriceShapeMismatchResponseSalonPriceMinBuilder> {
  _$ServicePriceShapeMismatchResponseSalonPriceMin? _$v;

  AnyOf? _anyOf;
  AnyOf? get anyOf => _$this._anyOf;
  set anyOf(AnyOf? anyOf) => _$this._anyOf = anyOf;

  ServicePriceShapeMismatchResponseSalonPriceMinBuilder() {
    ServicePriceShapeMismatchResponseSalonPriceMin._defaults(this);
  }

  ServicePriceShapeMismatchResponseSalonPriceMinBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _anyOf = $v.anyOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServicePriceShapeMismatchResponseSalonPriceMin other) {
    _$v = other as _$ServicePriceShapeMismatchResponseSalonPriceMin;
  }

  @override
  void update(
      void Function(ServicePriceShapeMismatchResponseSalonPriceMinBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ServicePriceShapeMismatchResponseSalonPriceMin build() => _build();

  _$ServicePriceShapeMismatchResponseSalonPriceMin _build() {
    final _$result = _$v ??
        _$ServicePriceShapeMismatchResponseSalonPriceMin._(
          anyOf: BuiltValueNullFieldError.checkNotNull(anyOf,
              r'ServicePriceShapeMismatchResponseSalonPriceMin', 'anyOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
