// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_favorite_salon_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseFavoriteSalonResponse
    extends ApiResponsePageResponseFavoriteSalonResponse {
  @override
  final bool? success;
  @override
  final PageResponseFavoriteSalonResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseFavoriteSalonResponse(
          [void Function(ApiResponsePageResponseFavoriteSalonResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseFavoriteSalonResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseFavoriteSalonResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseFavoriteSalonResponse rebuild(
          void Function(ApiResponsePageResponseFavoriteSalonResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseFavoriteSalonResponseBuilder toBuilder() =>
      ApiResponsePageResponseFavoriteSalonResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseFavoriteSalonResponse &&
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
            r'ApiResponsePageResponseFavoriteSalonResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseFavoriteSalonResponseBuilder
    implements
        Builder<ApiResponsePageResponseFavoriteSalonResponse,
            ApiResponsePageResponseFavoriteSalonResponseBuilder> {
  _$ApiResponsePageResponseFavoriteSalonResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseFavoriteSalonResponseBuilder? _data;
  PageResponseFavoriteSalonResponseBuilder get data =>
      _$this._data ??= PageResponseFavoriteSalonResponseBuilder();
  set data(PageResponseFavoriteSalonResponseBuilder? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseFavoriteSalonResponseBuilder() {
    ApiResponsePageResponseFavoriteSalonResponse._defaults(this);
  }

  ApiResponsePageResponseFavoriteSalonResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseFavoriteSalonResponse other) {
    _$v = other as _$ApiResponsePageResponseFavoriteSalonResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseFavoriteSalonResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseFavoriteSalonResponse build() => _build();

  _$ApiResponsePageResponseFavoriteSalonResponse _build() {
    _$ApiResponsePageResponseFavoriteSalonResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseFavoriteSalonResponse._(
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
            r'ApiResponsePageResponseFavoriteSalonResponse',
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
