// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_media_file_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageMediaFileResponse
    extends ApiResponsePageMediaFileResponse {
  @override
  final bool? success;
  @override
  final PageMediaFileResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageMediaFileResponse(
          [void Function(ApiResponsePageMediaFileResponseBuilder)? updates]) =>
      (ApiResponsePageMediaFileResponseBuilder()..update(updates))._build();

  _$ApiResponsePageMediaFileResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageMediaFileResponse rebuild(
          void Function(ApiResponsePageMediaFileResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageMediaFileResponseBuilder toBuilder() =>
      ApiResponsePageMediaFileResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageMediaFileResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponsePageMediaFileResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageMediaFileResponseBuilder
    implements
        Builder<ApiResponsePageMediaFileResponse,
            ApiResponsePageMediaFileResponseBuilder> {
  _$ApiResponsePageMediaFileResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageMediaFileResponseBuilder? _data;
  PageMediaFileResponseBuilder get data =>
      _$this._data ??= PageMediaFileResponseBuilder();
  set data(PageMediaFileResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageMediaFileResponseBuilder() {
    ApiResponsePageMediaFileResponse._defaults(this);
  }

  ApiResponsePageMediaFileResponseBuilder get _$this {
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
  void replace(ApiResponsePageMediaFileResponse other) {
    _$v = other as _$ApiResponsePageMediaFileResponse;
  }

  @override
  void update(void Function(ApiResponsePageMediaFileResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageMediaFileResponse build() => _build();

  _$ApiResponsePageMediaFileResponse _build() {
    _$ApiResponsePageMediaFileResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageMediaFileResponse._(
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
            r'ApiResponsePageMediaFileResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
