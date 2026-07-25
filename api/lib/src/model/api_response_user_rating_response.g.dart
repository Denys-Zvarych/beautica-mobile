// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_user_rating_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseUserRatingResponse extends ApiResponseUserRatingResponse {
  @override
  final bool? success;
  @override
  final UserRatingResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseUserRatingResponse(
          [void Function(ApiResponseUserRatingResponseBuilder)? updates]) =>
      (ApiResponseUserRatingResponseBuilder()..update(updates))._build();

  _$ApiResponseUserRatingResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseUserRatingResponse rebuild(
          void Function(ApiResponseUserRatingResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseUserRatingResponseBuilder toBuilder() =>
      ApiResponseUserRatingResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseUserRatingResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseUserRatingResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseUserRatingResponseBuilder
    implements
        Builder<ApiResponseUserRatingResponse,
            ApiResponseUserRatingResponseBuilder> {
  _$ApiResponseUserRatingResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  UserRatingResponseBuilder? _data;
  UserRatingResponseBuilder get data =>
      _$this._data ??= UserRatingResponseBuilder();
  set data(UserRatingResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseUserRatingResponseBuilder() {
    ApiResponseUserRatingResponse._defaults(this);
  }

  ApiResponseUserRatingResponseBuilder get _$this {
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
  void replace(ApiResponseUserRatingResponse other) {
    _$v = other as _$ApiResponseUserRatingResponse;
  }

  @override
  void update(void Function(ApiResponseUserRatingResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseUserRatingResponse build() => _build();

  _$ApiResponseUserRatingResponse _build() {
    _$ApiResponseUserRatingResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseUserRatingResponse._(
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
            r'ApiResponseUserRatingResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
