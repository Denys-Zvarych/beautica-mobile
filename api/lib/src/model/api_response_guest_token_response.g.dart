// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_guest_token_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseGuestTokenResponse extends ApiResponseGuestTokenResponse {
  @override
  final bool? success;
  @override
  final GuestTokenResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseGuestTokenResponse(
          [void Function(ApiResponseGuestTokenResponseBuilder)? updates]) =>
      (ApiResponseGuestTokenResponseBuilder()..update(updates))._build();

  _$ApiResponseGuestTokenResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseGuestTokenResponse rebuild(
          void Function(ApiResponseGuestTokenResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseGuestTokenResponseBuilder toBuilder() =>
      ApiResponseGuestTokenResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseGuestTokenResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseGuestTokenResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseGuestTokenResponseBuilder
    implements
        Builder<ApiResponseGuestTokenResponse,
            ApiResponseGuestTokenResponseBuilder> {
  _$ApiResponseGuestTokenResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  GuestTokenResponseBuilder? _data;
  GuestTokenResponseBuilder get data =>
      _$this._data ??= GuestTokenResponseBuilder();
  set data(GuestTokenResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseGuestTokenResponseBuilder() {
    ApiResponseGuestTokenResponse._defaults(this);
  }

  ApiResponseGuestTokenResponseBuilder get _$this {
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
  void replace(ApiResponseGuestTokenResponse other) {
    _$v = other as _$ApiResponseGuestTokenResponse;
  }

  @override
  void update(void Function(ApiResponseGuestTokenResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseGuestTokenResponse build() => _build();

  _$ApiResponseGuestTokenResponse _build() {
    _$ApiResponseGuestTokenResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseGuestTokenResponse._(
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
            r'ApiResponseGuestTokenResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
