// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_service_coverage.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonServiceCoverage extends SalonServiceCoverage {
  @override
  final String serviceId;
  @override
  final BuiltList<SalonServiceMasterRef> masters;

  factory _$SalonServiceCoverage(
          [void Function(SalonServiceCoverageBuilder)? updates]) =>
      (SalonServiceCoverageBuilder()..update(updates))._build();

  _$SalonServiceCoverage._({required this.serviceId, required this.masters})
      : super._();
  @override
  SalonServiceCoverage rebuild(
          void Function(SalonServiceCoverageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonServiceCoverageBuilder toBuilder() =>
      SalonServiceCoverageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonServiceCoverage &&
        serviceId == other.serviceId &&
        masters == other.masters;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, serviceId.hashCode);
    _$hash = $jc(_$hash, masters.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonServiceCoverage')
          ..add('serviceId', serviceId)
          ..add('masters', masters))
        .toString();
  }
}

class SalonServiceCoverageBuilder
    implements Builder<SalonServiceCoverage, SalonServiceCoverageBuilder> {
  _$SalonServiceCoverage? _$v;

  String? _serviceId;
  String? get serviceId => _$this._serviceId;
  set serviceId(String? serviceId) => _$this._serviceId = serviceId;

  ListBuilder<SalonServiceMasterRef>? _masters;
  ListBuilder<SalonServiceMasterRef> get masters =>
      _$this._masters ??= ListBuilder<SalonServiceMasterRef>();
  set masters(ListBuilder<SalonServiceMasterRef>? masters) =>
      _$this._masters = masters;

  SalonServiceCoverageBuilder() {
    SalonServiceCoverage._defaults(this);
  }

  SalonServiceCoverageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _serviceId = $v.serviceId;
      _masters = $v.masters.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonServiceCoverage other) {
    _$v = other as _$SalonServiceCoverage;
  }

  @override
  void update(void Function(SalonServiceCoverageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonServiceCoverage build() => _build();

  _$SalonServiceCoverage _build() {
    _$SalonServiceCoverage _$result;
    try {
      _$result = _$v ??
          _$SalonServiceCoverage._(
            serviceId: BuiltValueNullFieldError.checkNotNull(
                serviceId, r'SalonServiceCoverage', 'serviceId'),
            masters: masters.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'masters';
        masters.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonServiceCoverage', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
