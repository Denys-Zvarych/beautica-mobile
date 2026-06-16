// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_platform_service_type_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListPlatformServiceTypeResponse
    extends ApiResponseListPlatformServiceTypeResponse {
  @override
  final bool? success;
  @override
  final BuiltList<PlatformServiceTypeResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListPlatformServiceTypeResponse(
          [void Function(ApiResponseListPlatformServiceTypeResponseBuilder)?
              updates]) =>
      (ApiResponseListPlatformServiceTypeResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListPlatformServiceTypeResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListPlatformServiceTypeResponse rebuild(
          void Function(ApiResponseListPlatformServiceTypeResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListPlatformServiceTypeResponseBuilder toBuilder() =>
      ApiResponseListPlatformServiceTypeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListPlatformServiceTypeResponse &&
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
            r'ApiResponseListPlatformServiceTypeResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListPlatformServiceTypeResponseBuilder
    implements
        Builder<ApiResponseListPlatformServiceTypeResponse,
            ApiResponseListPlatformServiceTypeResponseBuilder> {
  _$ApiResponseListPlatformServiceTypeResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<PlatformServiceTypeResponse>? _data;
  ListBuilder<PlatformServiceTypeResponse> get data =>
      _$this._data ??= ListBuilder<PlatformServiceTypeResponse>();
  set data(ListBuilder<PlatformServiceTypeResponse>? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListPlatformServiceTypeResponseBuilder() {
    ApiResponseListPlatformServiceTypeResponse._defaults(this);
  }

  ApiResponseListPlatformServiceTypeResponseBuilder get _$this {
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
  void replace(ApiResponseListPlatformServiceTypeResponse other) {
    _$v = other as _$ApiResponseListPlatformServiceTypeResponse;
  }

  @override
  void update(
      void Function(ApiResponseListPlatformServiceTypeResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListPlatformServiceTypeResponse build() => _build();

  _$ApiResponseListPlatformServiceTypeResponse _build() {
    _$ApiResponseListPlatformServiceTypeResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListPlatformServiceTypeResponse._(
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
            r'ApiResponseListPlatformServiceTypeResponse',
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
