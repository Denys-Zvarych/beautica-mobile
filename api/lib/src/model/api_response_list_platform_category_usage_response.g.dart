// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_platform_category_usage_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListPlatformCategoryUsageResponse
    extends ApiResponseListPlatformCategoryUsageResponse {
  @override
  final bool? success;
  @override
  final BuiltList<PlatformCategoryUsageResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListPlatformCategoryUsageResponse(
          [void Function(ApiResponseListPlatformCategoryUsageResponseBuilder)?
              updates]) =>
      (ApiResponseListPlatformCategoryUsageResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListPlatformCategoryUsageResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListPlatformCategoryUsageResponse rebuild(
          void Function(ApiResponseListPlatformCategoryUsageResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListPlatformCategoryUsageResponseBuilder toBuilder() =>
      ApiResponseListPlatformCategoryUsageResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListPlatformCategoryUsageResponse &&
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
    return (newBuiltValueToStringHelper(
            r'ApiResponseListPlatformCategoryUsageResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListPlatformCategoryUsageResponseBuilder
    implements
        Builder<ApiResponseListPlatformCategoryUsageResponse,
            ApiResponseListPlatformCategoryUsageResponseBuilder> {
  _$ApiResponseListPlatformCategoryUsageResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<PlatformCategoryUsageResponse>? _data;
  ListBuilder<PlatformCategoryUsageResponse> get data =>
      _$this._data ??= ListBuilder<PlatformCategoryUsageResponse>();
  set data(ListBuilder<PlatformCategoryUsageResponse>? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListPlatformCategoryUsageResponseBuilder() {
    ApiResponseListPlatformCategoryUsageResponse._defaults(this);
  }

  ApiResponseListPlatformCategoryUsageResponseBuilder get _$this {
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
  void replace(ApiResponseListPlatformCategoryUsageResponse other) {
    _$v = other as _$ApiResponseListPlatformCategoryUsageResponse;
  }

  @override
  void update(
      void Function(ApiResponseListPlatformCategoryUsageResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListPlatformCategoryUsageResponse build() => _build();

  _$ApiResponseListPlatformCategoryUsageResponse _build() {
    _$ApiResponseListPlatformCategoryUsageResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListPlatformCategoryUsageResponse._(
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
            r'ApiResponseListPlatformCategoryUsageResponse',
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
