// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_price_shape_mismatch_error_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServicePriceShapeMismatchErrorResponse
    extends ServicePriceShapeMismatchErrorResponse {
  @override
  final bool? success;
  @override
  final ServicePriceShapeMismatchResponse? data;
  @override
  final String? message;

  factory _$ServicePriceShapeMismatchErrorResponse(
          [void Function(ServicePriceShapeMismatchErrorResponseBuilder)?
              updates]) =>
      (ServicePriceShapeMismatchErrorResponseBuilder()..update(updates))
          ._build();

  _$ServicePriceShapeMismatchErrorResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ServicePriceShapeMismatchErrorResponse rebuild(
          void Function(ServicePriceShapeMismatchErrorResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServicePriceShapeMismatchErrorResponseBuilder toBuilder() =>
      ServicePriceShapeMismatchErrorResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServicePriceShapeMismatchErrorResponse &&
        success == other.success &&
        data == other.data &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
            r'ServicePriceShapeMismatchErrorResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ServicePriceShapeMismatchErrorResponseBuilder
    implements
        Builder<ServicePriceShapeMismatchErrorResponse,
            ServicePriceShapeMismatchErrorResponseBuilder> {
  _$ServicePriceShapeMismatchErrorResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ServicePriceShapeMismatchResponseBuilder? _data;
  ServicePriceShapeMismatchResponseBuilder get data =>
      _$this._data ??= ServicePriceShapeMismatchResponseBuilder();
  set data(ServicePriceShapeMismatchResponseBuilder? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ServicePriceShapeMismatchErrorResponseBuilder() {
    ServicePriceShapeMismatchErrorResponse._defaults(this);
  }

  ServicePriceShapeMismatchErrorResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data?.toBuilder();
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServicePriceShapeMismatchErrorResponse other) {
    _$v = other as _$ServicePriceShapeMismatchErrorResponse;
  }

  @override
  void update(
      void Function(ServicePriceShapeMismatchErrorResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServicePriceShapeMismatchErrorResponse build() => _build();

  _$ServicePriceShapeMismatchErrorResponse _build() {
    _$ServicePriceShapeMismatchErrorResponse _$result;
    try {
      _$result = _$v ??
          _$ServicePriceShapeMismatchErrorResponse._(
            success: success,
            data: _data?.build(),
            message: message,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        _data?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ServicePriceShapeMismatchErrorResponse',
            _$failedField,
            e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
