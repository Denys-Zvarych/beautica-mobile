// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_favorite_service_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseFavoriteServiceResponse
    extends ApiResponsePageResponseFavoriteServiceResponse {
  @override
  final bool? success;
  @override
  final PageResponseFavoriteServiceResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseFavoriteServiceResponse(
          [void Function(ApiResponsePageResponseFavoriteServiceResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseFavoriteServiceResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseFavoriteServiceResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseFavoriteServiceResponse rebuild(
          void Function(ApiResponsePageResponseFavoriteServiceResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseFavoriteServiceResponseBuilder toBuilder() =>
      ApiResponsePageResponseFavoriteServiceResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseFavoriteServiceResponse &&
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
            r'ApiResponsePageResponseFavoriteServiceResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseFavoriteServiceResponseBuilder
    implements
        Builder<ApiResponsePageResponseFavoriteServiceResponse,
            ApiResponsePageResponseFavoriteServiceResponseBuilder> {
  _$ApiResponsePageResponseFavoriteServiceResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseFavoriteServiceResponseBuilder? _data;
  PageResponseFavoriteServiceResponseBuilder get data =>
      _$this._data ??= PageResponseFavoriteServiceResponseBuilder();
  set data(PageResponseFavoriteServiceResponseBuilder? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseFavoriteServiceResponseBuilder() {
    ApiResponsePageResponseFavoriteServiceResponse._defaults(this);
  }

  ApiResponsePageResponseFavoriteServiceResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseFavoriteServiceResponse other) {
    _$v = other as _$ApiResponsePageResponseFavoriteServiceResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseFavoriteServiceResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseFavoriteServiceResponse build() => _build();

  _$ApiResponsePageResponseFavoriteServiceResponse _build() {
    _$ApiResponsePageResponseFavoriteServiceResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseFavoriteServiceResponse._(
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
            r'ApiResponsePageResponseFavoriteServiceResponse',
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
