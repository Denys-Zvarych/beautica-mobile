// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_summary_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServiceSummaryDto extends ServiceSummaryDto {
  @override
  final String? id;
  @override
  final String? name;
  @override
  final int? durationMinutes;
  @override
  final num? priceFrom;

  factory _$ServiceSummaryDto(
          [void Function(ServiceSummaryDtoBuilder)? updates]) =>
      (ServiceSummaryDtoBuilder()..update(updates))._build();

  _$ServiceSummaryDto._(
      {this.id, this.name, this.durationMinutes, this.priceFrom})
      : super._();
  @override
  ServiceSummaryDto rebuild(void Function(ServiceSummaryDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServiceSummaryDtoBuilder toBuilder() =>
      ServiceSummaryDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServiceSummaryDto &&
        id == other.id &&
        name == other.name &&
        durationMinutes == other.durationMinutes &&
        priceFrom == other.priceFrom;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, durationMinutes.hashCode);
    _$hash = $jc(_$hash, priceFrom.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServiceSummaryDto')
          ..add('id', id)
          ..add('name', name)
          ..add('durationMinutes', durationMinutes)
          ..add('priceFrom', priceFrom))
        .toString();
  }
}

class ServiceSummaryDtoBuilder
    implements Builder<ServiceSummaryDto, ServiceSummaryDtoBuilder> {
  _$ServiceSummaryDto? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _durationMinutes;
  int? get durationMinutes => _$this._durationMinutes;
  set durationMinutes(int? durationMinutes) =>
      _$this._durationMinutes = durationMinutes;

  num? _priceFrom;
  num? get priceFrom => _$this._priceFrom;
  set priceFrom(num? priceFrom) => _$this._priceFrom = priceFrom;

  ServiceSummaryDtoBuilder() {
    ServiceSummaryDto._defaults(this);
  }

  ServiceSummaryDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _durationMinutes = $v.durationMinutes;
      _priceFrom = $v.priceFrom;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServiceSummaryDto other) {
    _$v = other as _$ServiceSummaryDto;
  }

  @override
  void update(void Function(ServiceSummaryDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServiceSummaryDto build() => _build();

  _$ServiceSummaryDto _build() {
    final _$result = _$v ??
        _$ServiceSummaryDto._(
          id: id,
          name: name,
          durationMinutes: durationMinutes,
          priceFrom: priceFrom,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
