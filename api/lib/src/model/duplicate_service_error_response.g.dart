// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duplicate_service_error_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DuplicateServiceErrorResponse extends DuplicateServiceErrorResponse {
  @override
  final bool? success;
  @override
  final DuplicateServiceResponse? data;
  @override
  final String? message;

  factory _$DuplicateServiceErrorResponse(
          [void Function(DuplicateServiceErrorResponseBuilder)? updates]) =>
      (DuplicateServiceErrorResponseBuilder()..update(updates))._build();

  _$DuplicateServiceErrorResponse._({this.success, this.data, this.message})
      : super._();
  @override
  DuplicateServiceErrorResponse rebuild(
          void Function(DuplicateServiceErrorResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DuplicateServiceErrorResponseBuilder toBuilder() =>
      DuplicateServiceErrorResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DuplicateServiceErrorResponse &&
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
    return (newBuiltValueToStringHelper(r'DuplicateServiceErrorResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class DuplicateServiceErrorResponseBuilder
    implements
        Builder<DuplicateServiceErrorResponse,
            DuplicateServiceErrorResponseBuilder> {
  _$DuplicateServiceErrorResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  DuplicateServiceResponseBuilder? _data;
  DuplicateServiceResponseBuilder get data =>
      _$this._data ??= DuplicateServiceResponseBuilder();
  set data(DuplicateServiceResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  DuplicateServiceErrorResponseBuilder() {
    DuplicateServiceErrorResponse._defaults(this);
  }

  DuplicateServiceErrorResponseBuilder get _$this {
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
  void replace(DuplicateServiceErrorResponse other) {
    _$v = other as _$DuplicateServiceErrorResponse;
  }

  @override
  void update(void Function(DuplicateServiceErrorResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DuplicateServiceErrorResponse build() => _build();

  _$DuplicateServiceErrorResponse _build() {
    _$DuplicateServiceErrorResponse _$result;
    try {
      _$result = _$v ??
          _$DuplicateServiceErrorResponse._(
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
            r'DuplicateServiceErrorResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
