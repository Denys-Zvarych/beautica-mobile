// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rotate_master_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RotateMasterRequest extends RotateMasterRequest {
  @override
  final String destinationSalonId;

  factory _$RotateMasterRequest(
          [void Function(RotateMasterRequestBuilder)? updates]) =>
      (RotateMasterRequestBuilder()..update(updates))._build();

  _$RotateMasterRequest._({required this.destinationSalonId}) : super._();
  @override
  RotateMasterRequest rebuild(
          void Function(RotateMasterRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RotateMasterRequestBuilder toBuilder() =>
      RotateMasterRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RotateMasterRequest &&
        destinationSalonId == other.destinationSalonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, destinationSalonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RotateMasterRequest')
          ..add('destinationSalonId', destinationSalonId))
        .toString();
  }
}

class RotateMasterRequestBuilder
    implements Builder<RotateMasterRequest, RotateMasterRequestBuilder> {
  _$RotateMasterRequest? _$v;

  String? _destinationSalonId;
  String? get destinationSalonId => _$this._destinationSalonId;
  set destinationSalonId(String? destinationSalonId) =>
      _$this._destinationSalonId = destinationSalonId;

  RotateMasterRequestBuilder() {
    RotateMasterRequest._defaults(this);
  }

  RotateMasterRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _destinationSalonId = $v.destinationSalonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RotateMasterRequest other) {
    _$v = other as _$RotateMasterRequest;
  }

  @override
  void update(void Function(RotateMasterRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RotateMasterRequest build() => _build();

  _$RotateMasterRequest _build() {
    final _$result = _$v ??
        _$RotateMasterRequest._(
          destinationSalonId: BuiltValueNullFieldError.checkNotNull(
              destinationSalonId, r'RotateMasterRequest', 'destinationSalonId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
