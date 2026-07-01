// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_favorite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseFavoriteResponse extends ApiResponseFavoriteResponse {
  @override
  final bool? success;
  @override
  final FavoriteResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseFavoriteResponse(
          [void Function(ApiResponseFavoriteResponseBuilder)? updates]) =>
      (ApiResponseFavoriteResponseBuilder()..update(updates))._build();

  _$ApiResponseFavoriteResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseFavoriteResponse rebuild(
          void Function(ApiResponseFavoriteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseFavoriteResponseBuilder toBuilder() =>
      ApiResponseFavoriteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseFavoriteResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseFavoriteResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseFavoriteResponseBuilder
    implements
        Builder<ApiResponseFavoriteResponse,
            ApiResponseFavoriteResponseBuilder> {
  _$ApiResponseFavoriteResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  FavoriteResponseBuilder? _data;
  FavoriteResponseBuilder get data =>
      _$this._data ??= FavoriteResponseBuilder();
  set data(FavoriteResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseFavoriteResponseBuilder() {
    ApiResponseFavoriteResponse._defaults(this);
  }

  ApiResponseFavoriteResponseBuilder get _$this {
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
  void replace(ApiResponseFavoriteResponse other) {
    _$v = other as _$ApiResponseFavoriteResponse;
  }

  @override
  void update(void Function(ApiResponseFavoriteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseFavoriteResponse build() => _build();

  _$ApiResponseFavoriteResponse _build() {
    _$ApiResponseFavoriteResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseFavoriteResponse._(
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
            r'ApiResponseFavoriteResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
