// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_public_salon_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePublicSalonResponse extends ApiResponsePublicSalonResponse {
  @override
  final bool? success;
  @override
  final PublicSalonResponse? data;
  @override
  final String? message;

  factory _$ApiResponsePublicSalonResponse(
          [void Function(ApiResponsePublicSalonResponseBuilder)? updates]) =>
      (ApiResponsePublicSalonResponseBuilder()..update(updates))._build();

  _$ApiResponsePublicSalonResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponsePublicSalonResponse rebuild(
          void Function(ApiResponsePublicSalonResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePublicSalonResponseBuilder toBuilder() =>
      ApiResponsePublicSalonResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePublicSalonResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponsePublicSalonResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponsePublicSalonResponseBuilder
    implements
        Builder<ApiResponsePublicSalonResponse,
            ApiResponsePublicSalonResponseBuilder> {
  _$ApiResponsePublicSalonResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PublicSalonResponseBuilder? _data;
  PublicSalonResponseBuilder get data =>
      _$this._data ??= PublicSalonResponseBuilder();
  set data(PublicSalonResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponsePublicSalonResponseBuilder() {
    ApiResponsePublicSalonResponse._defaults(this);
  }

  ApiResponsePublicSalonResponseBuilder get _$this {
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
  void replace(ApiResponsePublicSalonResponse other) {
    _$v = other as _$ApiResponsePublicSalonResponse;
  }

  @override
  void update(void Function(ApiResponsePublicSalonResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePublicSalonResponse build() => _build();

  _$ApiResponsePublicSalonResponse _build() {
    _$ApiResponsePublicSalonResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePublicSalonResponse._(
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
            r'ApiResponsePublicSalonResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
