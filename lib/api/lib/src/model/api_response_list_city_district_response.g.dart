// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_city_district_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListCityDistrictResponse
    extends ApiResponseListCityDistrictResponse {
  @override
  final bool? success;
  @override
  final BuiltList<CityDistrictResponse>? data;
  @override
  final String? message;

  factory _$ApiResponseListCityDistrictResponse(
          [void Function(ApiResponseListCityDistrictResponseBuilder)?
              updates]) =>
      (ApiResponseListCityDistrictResponseBuilder()..update(updates))._build();

  _$ApiResponseListCityDistrictResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseListCityDistrictResponse rebuild(
          void Function(ApiResponseListCityDistrictResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListCityDistrictResponseBuilder toBuilder() =>
      ApiResponseListCityDistrictResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListCityDistrictResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListCityDistrictResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseListCityDistrictResponseBuilder
    implements
        Builder<ApiResponseListCityDistrictResponse,
            ApiResponseListCityDistrictResponseBuilder> {
  _$ApiResponseListCityDistrictResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<CityDistrictResponse>? _data;
  ListBuilder<CityDistrictResponse> get data =>
      _$this._data ??= ListBuilder<CityDistrictResponse>();
  set data(ListBuilder<CityDistrictResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseListCityDistrictResponseBuilder() {
    ApiResponseListCityDistrictResponse._defaults(this);
  }

  ApiResponseListCityDistrictResponseBuilder get _$this {
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
  void replace(ApiResponseListCityDistrictResponse other) {
    _$v = other as _$ApiResponseListCityDistrictResponse;
  }

  @override
  void update(
      void Function(ApiResponseListCityDistrictResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListCityDistrictResponse build() => _build();

  _$ApiResponseListCityDistrictResponse _build() {
    _$ApiResponseListCityDistrictResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListCityDistrictResponse._(
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
        throw BuiltValueNestedFieldError(r'ApiResponseListCityDistrictResponse',
            _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
