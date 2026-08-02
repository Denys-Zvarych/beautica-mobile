// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_unclosed_count_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseUnclosedCountResponse
    extends ApiResponseUnclosedCountResponse {
  @override
  final bool? success;
  @override
  final UnclosedCountResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseUnclosedCountResponse(
          [void Function(ApiResponseUnclosedCountResponseBuilder)? updates]) =>
      (ApiResponseUnclosedCountResponseBuilder()..update(updates))._build();

  _$ApiResponseUnclosedCountResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseUnclosedCountResponse rebuild(
          void Function(ApiResponseUnclosedCountResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseUnclosedCountResponseBuilder toBuilder() =>
      ApiResponseUnclosedCountResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseUnclosedCountResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseUnclosedCountResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseUnclosedCountResponseBuilder
    implements
        Builder<ApiResponseUnclosedCountResponse,
            ApiResponseUnclosedCountResponseBuilder> {
  _$ApiResponseUnclosedCountResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  UnclosedCountResponseBuilder? _data;
  UnclosedCountResponseBuilder get data =>
      _$this._data ??= UnclosedCountResponseBuilder();
  set data(UnclosedCountResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseUnclosedCountResponseBuilder() {
    ApiResponseUnclosedCountResponse._defaults(this);
  }

  ApiResponseUnclosedCountResponseBuilder get _$this {
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
  void replace(ApiResponseUnclosedCountResponse other) {
    _$v = other as _$ApiResponseUnclosedCountResponse;
  }

  @override
  void update(void Function(ApiResponseUnclosedCountResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseUnclosedCountResponse build() => _build();

  _$ApiResponseUnclosedCountResponse _build() {
    _$ApiResponseUnclosedCountResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseUnclosedCountResponse._(
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
            r'ApiResponseUnclosedCountResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
