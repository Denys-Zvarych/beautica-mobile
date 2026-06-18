// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_favorite_master_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseFavoriteMasterResponse
    extends ApiResponsePageResponseFavoriteMasterResponse {
  @override
  final bool? success;
  @override
  final PageResponseFavoriteMasterResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseFavoriteMasterResponse(
          [void Function(ApiResponsePageResponseFavoriteMasterResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseFavoriteMasterResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseFavoriteMasterResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseFavoriteMasterResponse rebuild(
          void Function(ApiResponsePageResponseFavoriteMasterResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseFavoriteMasterResponseBuilder toBuilder() =>
      ApiResponsePageResponseFavoriteMasterResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseFavoriteMasterResponse &&
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
            r'ApiResponsePageResponseFavoriteMasterResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseFavoriteMasterResponseBuilder
    implements
        Builder<ApiResponsePageResponseFavoriteMasterResponse,
            ApiResponsePageResponseFavoriteMasterResponseBuilder> {
  _$ApiResponsePageResponseFavoriteMasterResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseFavoriteMasterResponseBuilder? _data;
  PageResponseFavoriteMasterResponseBuilder get data =>
      _$this._data ??= PageResponseFavoriteMasterResponseBuilder();
  set data(PageResponseFavoriteMasterResponseBuilder? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseFavoriteMasterResponseBuilder() {
    ApiResponsePageResponseFavoriteMasterResponse._defaults(this);
  }

  ApiResponsePageResponseFavoriteMasterResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseFavoriteMasterResponse other) {
    _$v = other as _$ApiResponsePageResponseFavoriteMasterResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseFavoriteMasterResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseFavoriteMasterResponse build() => _build();

  _$ApiResponsePageResponseFavoriteMasterResponse _build() {
    _$ApiResponsePageResponseFavoriteMasterResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseFavoriteMasterResponse._(
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
            r'ApiResponsePageResponseFavoriteMasterResponse',
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
