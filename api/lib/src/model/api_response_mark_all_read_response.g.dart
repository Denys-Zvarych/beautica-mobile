// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_mark_all_read_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseMarkAllReadResponse extends ApiResponseMarkAllReadResponse {
  @override
  final bool? success;
  @override
  final MarkAllReadResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseMarkAllReadResponse(
          [void Function(ApiResponseMarkAllReadResponseBuilder)? updates]) =>
      (ApiResponseMarkAllReadResponseBuilder()..update(updates))._build();

  _$ApiResponseMarkAllReadResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseMarkAllReadResponse rebuild(
          void Function(ApiResponseMarkAllReadResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseMarkAllReadResponseBuilder toBuilder() =>
      ApiResponseMarkAllReadResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseMarkAllReadResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseMarkAllReadResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseMarkAllReadResponseBuilder
    implements
        Builder<ApiResponseMarkAllReadResponse,
            ApiResponseMarkAllReadResponseBuilder> {
  _$ApiResponseMarkAllReadResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  MarkAllReadResponseBuilder? _data;
  MarkAllReadResponseBuilder get data =>
      _$this._data ??= MarkAllReadResponseBuilder();
  set data(MarkAllReadResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseMarkAllReadResponseBuilder() {
    ApiResponseMarkAllReadResponse._defaults(this);
  }

  ApiResponseMarkAllReadResponseBuilder get _$this {
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
  void replace(ApiResponseMarkAllReadResponse other) {
    _$v = other as _$ApiResponseMarkAllReadResponse;
  }

  @override
  void update(void Function(ApiResponseMarkAllReadResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseMarkAllReadResponse build() => _build();

  _$ApiResponseMarkAllReadResponse _build() {
    _$ApiResponseMarkAllReadResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseMarkAllReadResponse._(
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
            r'ApiResponseMarkAllReadResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
