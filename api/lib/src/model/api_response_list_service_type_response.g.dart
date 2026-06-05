// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_service_type_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListServiceTypeResponse
    extends ApiResponseListServiceTypeResponse {
  @override
  final bool? success;
  @override
  final BuiltList<ServiceTypeResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListServiceTypeResponse(
          [void Function(ApiResponseListServiceTypeResponseBuilder)?
              updates]) =>
      (ApiResponseListServiceTypeResponseBuilder()..update(updates))._build();

  _$ApiResponseListServiceTypeResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListServiceTypeResponse rebuild(
          void Function(ApiResponseListServiceTypeResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListServiceTypeResponseBuilder toBuilder() =>
      ApiResponseListServiceTypeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListServiceTypeResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListServiceTypeResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListServiceTypeResponseBuilder
    implements
        Builder<ApiResponseListServiceTypeResponse,
            ApiResponseListServiceTypeResponseBuilder> {
  _$ApiResponseListServiceTypeResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<ServiceTypeResponse>? _data;
  ListBuilder<ServiceTypeResponse> get data =>
      _$this._data ??= ListBuilder<ServiceTypeResponse>();
  set data(ListBuilder<ServiceTypeResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListServiceTypeResponseBuilder() {
    ApiResponseListServiceTypeResponse._defaults(this);
  }

  ApiResponseListServiceTypeResponseBuilder get _$this {
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
  void replace(ApiResponseListServiceTypeResponse other) {
    _$v = other as _$ApiResponseListServiceTypeResponse;
  }

  @override
  void update(
      void Function(ApiResponseListServiceTypeResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListServiceTypeResponse build() => _build();

  _$ApiResponseListServiceTypeResponse _build() {
    _$ApiResponseListServiceTypeResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListServiceTypeResponse._(
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
            r'ApiResponseListServiceTypeResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
