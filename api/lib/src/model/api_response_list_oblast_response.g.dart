// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_oblast_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListOblastResponse extends ApiResponseListOblastResponse {
  @override
  final bool? success;
  @override
  final BuiltList<OblastResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListOblastResponse(
          [void Function(ApiResponseListOblastResponseBuilder)? updates]) =>
      (ApiResponseListOblastResponseBuilder()..update(updates))._build();

  _$ApiResponseListOblastResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListOblastResponse rebuild(
          void Function(ApiResponseListOblastResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListOblastResponseBuilder toBuilder() =>
      ApiResponseListOblastResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListOblastResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListOblastResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListOblastResponseBuilder
    implements
        Builder<ApiResponseListOblastResponse,
            ApiResponseListOblastResponseBuilder> {
  _$ApiResponseListOblastResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<OblastResponse>? _data;
  ListBuilder<OblastResponse> get data =>
      _$this._data ??= ListBuilder<OblastResponse>();
  set data(ListBuilder<OblastResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListOblastResponseBuilder() {
    ApiResponseListOblastResponse._defaults(this);
  }

  ApiResponseListOblastResponseBuilder get _$this {
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
  void replace(ApiResponseListOblastResponse other) {
    _$v = other as _$ApiResponseListOblastResponse;
  }

  @override
  void update(void Function(ApiResponseListOblastResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListOblastResponse build() => _build();

  _$ApiResponseListOblastResponse _build() {
    _$ApiResponseListOblastResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListOblastResponse._(
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
            r'ApiResponseListOblastResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
