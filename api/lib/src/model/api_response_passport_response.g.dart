// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_passport_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePassportResponse extends ApiResponsePassportResponse {
  @override
  final bool? success;
  @override
  final PassportResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePassportResponse(
          [void Function(ApiResponsePassportResponseBuilder)? updates]) =>
      (ApiResponsePassportResponseBuilder()..update(updates))._build();

  _$ApiResponsePassportResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePassportResponse rebuild(
          void Function(ApiResponsePassportResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePassportResponseBuilder toBuilder() =>
      ApiResponsePassportResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePassportResponse &&
        success == other.success &&
        data == other.data &&
        message == other.message &&
        errors == other.errors;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, errors.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApiResponsePassportResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePassportResponseBuilder
    implements
        Builder<ApiResponsePassportResponse,
            ApiResponsePassportResponseBuilder> {
  _$ApiResponsePassportResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PassportResponseBuilder? _data;
  PassportResponseBuilder get data =>
      _$this._data ??= PassportResponseBuilder();
  set data(PassportResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePassportResponseBuilder() {
    ApiResponsePassportResponse._defaults(this);
  }

  ApiResponsePassportResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data?.toBuilder();
      _message = $v.message;
      _errors = $v.errors?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiResponsePassportResponse other) {
    _$v = other as _$ApiResponsePassportResponse;
  }

  @override
  void update(void Function(ApiResponsePassportResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePassportResponse build() => _build();

  _$ApiResponsePassportResponse _build() {
    _$ApiResponsePassportResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePassportResponse._(
            success: success,
            data: _data?.build(),
            message: message,
            errors: _errors?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        _data?.build();

        _$failedField = 'errors';
        _errors?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApiResponsePassportResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
