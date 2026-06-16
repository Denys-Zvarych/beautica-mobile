// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_invite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseInviteResponse extends ApiResponseInviteResponse {
  @override
  final bool? success;
  @override
  final InviteResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseInviteResponse(
          [void Function(ApiResponseInviteResponseBuilder)? updates]) =>
      (ApiResponseInviteResponseBuilder()..update(updates))._build();

  _$ApiResponseInviteResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseInviteResponse rebuild(
          void Function(ApiResponseInviteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseInviteResponseBuilder toBuilder() =>
      ApiResponseInviteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseInviteResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseInviteResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseInviteResponseBuilder
    implements
        Builder<ApiResponseInviteResponse, ApiResponseInviteResponseBuilder> {
  _$ApiResponseInviteResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  InviteResponseBuilder? _data;
  InviteResponseBuilder get data => _$this._data ??= InviteResponseBuilder();
  set data(InviteResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseInviteResponseBuilder() {
    ApiResponseInviteResponse._defaults(this);
  }

  ApiResponseInviteResponseBuilder get _$this {
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
  void replace(ApiResponseInviteResponse other) {
    _$v = other as _$ApiResponseInviteResponse;
  }

  @override
  void update(void Function(ApiResponseInviteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseInviteResponse build() => _build();

  _$ApiResponseInviteResponse _build() {
    _$ApiResponseInviteResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseInviteResponse._(
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
            r'ApiResponseInviteResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
