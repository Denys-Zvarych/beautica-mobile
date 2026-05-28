// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_registration_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseRegistrationResponse
    extends ApiResponseRegistrationResponse {
  @override
  final bool? success;
  @override
  final RegistrationResponse? data;
  @override
  final String? message;

  factory _$ApiResponseRegistrationResponse(
          [void Function(ApiResponseRegistrationResponseBuilder)? updates]) =>
      (ApiResponseRegistrationResponseBuilder()..update(updates))._build();

  _$ApiResponseRegistrationResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseRegistrationResponse rebuild(
          void Function(ApiResponseRegistrationResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseRegistrationResponseBuilder toBuilder() =>
      ApiResponseRegistrationResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseRegistrationResponse &&
        success == other.success &&
        data == other.data &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApiResponseRegistrationResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseRegistrationResponseBuilder
    implements
        Builder<ApiResponseRegistrationResponse,
            ApiResponseRegistrationResponseBuilder> {
  _$ApiResponseRegistrationResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  RegistrationResponseBuilder? _data;
  RegistrationResponseBuilder get data =>
      _$this._data ??= RegistrationResponseBuilder();
  set data(RegistrationResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseRegistrationResponseBuilder() {
    ApiResponseRegistrationResponse._defaults(this);
  }

  ApiResponseRegistrationResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data?.toBuilder();
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiResponseRegistrationResponse other) {
    _$v = other as _$ApiResponseRegistrationResponse;
  }

  @override
  void update(void Function(ApiResponseRegistrationResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseRegistrationResponse build() => _build();

  _$ApiResponseRegistrationResponse _build() {
    _$ApiResponseRegistrationResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseRegistrationResponse._(
            success: success,
            data: _data?.build(),
            message: message,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        _data?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApiResponseRegistrationResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
