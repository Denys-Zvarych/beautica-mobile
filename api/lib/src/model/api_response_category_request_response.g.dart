// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_category_request_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseCategoryRequestResponse
    extends ApiResponseCategoryRequestResponse {
  @override
  final bool? success;
  @override
  final CategoryRequestResponse? data;
  @override
  final String? message;

  factory _$ApiResponseCategoryRequestResponse(
          [void Function(ApiResponseCategoryRequestResponseBuilder)?
              updates]) =>
      (ApiResponseCategoryRequestResponseBuilder()..update(updates))._build();

  _$ApiResponseCategoryRequestResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseCategoryRequestResponse rebuild(
          void Function(ApiResponseCategoryRequestResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseCategoryRequestResponseBuilder toBuilder() =>
      ApiResponseCategoryRequestResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseCategoryRequestResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseCategoryRequestResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseCategoryRequestResponseBuilder
    implements
        Builder<ApiResponseCategoryRequestResponse,
            ApiResponseCategoryRequestResponseBuilder> {
  _$ApiResponseCategoryRequestResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  CategoryRequestResponseBuilder? _data;
  CategoryRequestResponseBuilder get data =>
      _$this._data ??= CategoryRequestResponseBuilder();
  set data(CategoryRequestResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseCategoryRequestResponseBuilder() {
    ApiResponseCategoryRequestResponse._defaults(this);
  }

  ApiResponseCategoryRequestResponseBuilder get _$this {
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
  void replace(ApiResponseCategoryRequestResponse other) {
    _$v = other as _$ApiResponseCategoryRequestResponse;
  }

  @override
  void update(
      void Function(ApiResponseCategoryRequestResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseCategoryRequestResponse build() => _build();

  _$ApiResponseCategoryRequestResponse _build() {
    _$ApiResponseCategoryRequestResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseCategoryRequestResponse._(
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
            r'ApiResponseCategoryRequestResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
