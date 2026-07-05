// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_verify_password_reset_otp_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseVerifyPasswordResetOtpResponse
    extends ApiResponseVerifyPasswordResetOtpResponse {
  @override
  final bool? success;
  @override
  final VerifyPasswordResetOtpResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseVerifyPasswordResetOtpResponse(
          [void Function(ApiResponseVerifyPasswordResetOtpResponseBuilder)?
              updates]) =>
      (ApiResponseVerifyPasswordResetOtpResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseVerifyPasswordResetOtpResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseVerifyPasswordResetOtpResponse rebuild(
          void Function(ApiResponseVerifyPasswordResetOtpResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseVerifyPasswordResetOtpResponseBuilder toBuilder() =>
      ApiResponseVerifyPasswordResetOtpResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseVerifyPasswordResetOtpResponse &&
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
            r'ApiResponseVerifyPasswordResetOtpResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseVerifyPasswordResetOtpResponseBuilder
    implements
        Builder<ApiResponseVerifyPasswordResetOtpResponse,
            ApiResponseVerifyPasswordResetOtpResponseBuilder> {
  _$ApiResponseVerifyPasswordResetOtpResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  VerifyPasswordResetOtpResponseBuilder? _data;
  VerifyPasswordResetOtpResponseBuilder get data =>
      _$this._data ??= VerifyPasswordResetOtpResponseBuilder();
  set data(VerifyPasswordResetOtpResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseVerifyPasswordResetOtpResponseBuilder() {
    ApiResponseVerifyPasswordResetOtpResponse._defaults(this);
  }

  ApiResponseVerifyPasswordResetOtpResponseBuilder get _$this {
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
  void replace(ApiResponseVerifyPasswordResetOtpResponse other) {
    _$v = other as _$ApiResponseVerifyPasswordResetOtpResponse;
  }

  @override
  void update(
      void Function(ApiResponseVerifyPasswordResetOtpResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseVerifyPasswordResetOtpResponse build() => _build();

  _$ApiResponseVerifyPasswordResetOtpResponse _build() {
    _$ApiResponseVerifyPasswordResetOtpResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseVerifyPasswordResetOtpResponse._(
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
            r'ApiResponseVerifyPasswordResetOtpResponse',
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
