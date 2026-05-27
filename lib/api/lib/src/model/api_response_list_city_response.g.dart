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

  factory _$ApiResponseListCityResponse(
          [void Function(ApiResponseListCityResponseBuilder)? updates]) =>
      (ApiResponseListCityResponseBuilder()..update(updates))._build();

  _$ApiResponseListCityResponse._({this.success, this.data, this.message})
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
    return (newBuiltValueToStringHelper(r'ApiResponseListCityResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
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

  ApiResponseListCityResponseBuilder() {
    ApiResponseListCityResponse._defaults(this);
  }

  ApiResponseListCityResponseBuilder get _$this {
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
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        _data?.build();
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
