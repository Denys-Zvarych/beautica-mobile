// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rotate_admin_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RotateAdminRequest extends RotateAdminRequest {
  @override
  final String destinationSalonId;

  factory _$RotateAdminRequest(
          [void Function(RotateAdminRequestBuilder)? updates]) =>
      (RotateAdminRequestBuilder()..update(updates))._build();

  _$RotateAdminRequest._({required this.destinationSalonId}) : super._();
  @override
  RotateAdminRequest rebuild(
          void Function(RotateAdminRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RotateAdminRequestBuilder toBuilder() =>
      RotateAdminRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RotateAdminRequest &&
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
    return (newBuiltValueToStringHelper(r'RotateAdminRequest')
          ..add('destinationSalonId', destinationSalonId))
        .toString();
  }
}

class RotateAdminRequestBuilder
    implements Builder<RotateAdminRequest, RotateAdminRequestBuilder> {
  _$RotateAdminRequest? _$v;

  String? _destinationSalonId;
  String? get destinationSalonId => _$this._destinationSalonId;
  set destinationSalonId(String? destinationSalonId) =>
      _$this._destinationSalonId = destinationSalonId;

  RotateAdminRequestBuilder() {
    RotateAdminRequest._defaults(this);
  }

  RotateAdminRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _destinationSalonId = $v.destinationSalonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RotateAdminRequest other) {
    _$v = other as _$RotateAdminRequest;
  }

  @override
  void update(void Function(RotateAdminRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RotateAdminRequest build() => _build();

  _$RotateAdminRequest _build() {
    final _$result = _$v ??
        _$RotateAdminRequest._(
          destinationSalonId: BuiltValueNullFieldError.checkNotNull(
              destinationSalonId, r'RotateAdminRequest', 'destinationSalonId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
