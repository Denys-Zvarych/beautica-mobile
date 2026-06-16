// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_city_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListCityResponse extends ApiResponseListCityResponse {
  @override
  final bool? success;
  @override
  final BuiltList<CityResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListCityResponse(
          [void Function(ApiResponseListCityResponseBuilder)? updates]) =>
      (ApiResponseListCityResponseBuilder()..update(updates))._build();

  _$ApiResponseListCityResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListCityResponse rebuild(
          void Function(ApiResponseListCityResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListCityResponseBuilder toBuilder() =>
      ApiResponseListCityResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListCityResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListCityResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListCityResponseBuilder
    implements
        Builder<ApiResponseListCityResponse,
            ApiResponseListCityResponseBuilder> {
  _$ApiResponseListCityResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<CityResponse>? _data;
  ListBuilder<CityResponse> get data =>
      _$this._data ??= ListBuilder<CityResponse>();
  set data(ListBuilder<CityResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListCityResponseBuilder() {
    ApiResponseListCityResponse._defaults(this);
  }

  ApiResponseListCityResponseBuilder get _$this {
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
  void replace(ApiResponseListCityResponse other) {
    _$v = other as _$ApiResponseListCityResponse;
  }

  @override
  void update(void Function(ApiResponseListCityResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListCityResponse build() => _build();

  _$ApiResponseListCityResponse _build() {
    _$ApiResponseListCityResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListCityResponse._(
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
            r'ApiResponseListCityResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
