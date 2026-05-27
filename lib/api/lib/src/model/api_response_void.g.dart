// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_void.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseVoid extends ApiResponseVoid {
  @override
  final bool? success;
  @override
  final JsonObject? data;
  @override
  final String? message;

  factory _$ApiResponseVoid([void Function(ApiResponseVoidBuilder)? updates]) =>
      (ApiResponseVoidBuilder()..update(updates))._build();

  _$ApiResponseVoid._({this.success, this.data, this.message}) : super._();
  @override
  ApiResponseVoid rebuild(void Function(ApiResponseVoidBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseVoidBuilder toBuilder() => ApiResponseVoidBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseVoid &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseVoid')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseVoidBuilder
    implements Builder<ApiResponseVoid, ApiResponseVoidBuilder> {
  _$ApiResponseVoid? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  JsonObject? _data;
  JsonObject? get data => _$this._data;
  set data(JsonObject? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseVoidBuilder() {
    ApiResponseVoid._defaults(this);
  }

  ApiResponseVoidBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiResponseVoid other) {
    _$v = other as _$ApiResponseVoid;
  }

  @override
  void update(void Function(ApiResponseVoidBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseVoid build() => _build();

  _$ApiResponseVoid _build() {
    final _$result = _$v ??
        _$ApiResponseVoid._(
          success: success,
          data: data,
          message: message,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
