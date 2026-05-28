// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_media_file_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseMediaFileResponse extends ApiResponseMediaFileResponse {
  @override
  final bool? success;
  @override
  final MediaFileResponse? data;
  @override
  final String? message;

  factory _$ApiResponseMediaFileResponse(
          [void Function(ApiResponseMediaFileResponseBuilder)? updates]) =>
      (ApiResponseMediaFileResponseBuilder()..update(updates))._build();

  _$ApiResponseMediaFileResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseMediaFileResponse rebuild(
          void Function(ApiResponseMediaFileResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseMediaFileResponseBuilder toBuilder() =>
      ApiResponseMediaFileResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseMediaFileResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseMediaFileResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseMediaFileResponseBuilder
    implements
        Builder<ApiResponseMediaFileResponse,
            ApiResponseMediaFileResponseBuilder> {
  _$ApiResponseMediaFileResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  MediaFileResponseBuilder? _data;
  MediaFileResponseBuilder get data =>
      _$this._data ??= MediaFileResponseBuilder();
  set data(MediaFileResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseMediaFileResponseBuilder() {
    ApiResponseMediaFileResponse._defaults(this);
  }

  ApiResponseMediaFileResponseBuilder get _$this {
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
  void replace(ApiResponseMediaFileResponse other) {
    _$v = other as _$ApiResponseMediaFileResponse;
  }

  @override
  void update(void Function(ApiResponseMediaFileResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseMediaFileResponse build() => _build();

  _$ApiResponseMediaFileResponse _build() {
    _$ApiResponseMediaFileResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseMediaFileResponse._(
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
            r'ApiResponseMediaFileResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
