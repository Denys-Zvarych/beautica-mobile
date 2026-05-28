// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_salon_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseSalonResponse extends ApiResponseSalonResponse {
  @override
  final bool? success;
  @override
  final SalonResponse? data;
  @override
  final String? message;

  factory _$ApiResponseSalonResponse(
          [void Function(ApiResponseSalonResponseBuilder)? updates]) =>
      (ApiResponseSalonResponseBuilder()..update(updates))._build();

  _$ApiResponseSalonResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseSalonResponse rebuild(
          void Function(ApiResponseSalonResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseSalonResponseBuilder toBuilder() =>
      ApiResponseSalonResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseSalonResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseSalonResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseSalonResponseBuilder
    implements
        Builder<ApiResponseSalonResponse, ApiResponseSalonResponseBuilder> {
  _$ApiResponseSalonResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  SalonResponseBuilder? _data;
  SalonResponseBuilder get data => _$this._data ??= SalonResponseBuilder();
  set data(SalonResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseSalonResponseBuilder() {
    ApiResponseSalonResponse._defaults(this);
  }

  ApiResponseSalonResponseBuilder get _$this {
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
  void replace(ApiResponseSalonResponse other) {
    _$v = other as _$ApiResponseSalonResponse;
  }

  @override
  void update(void Function(ApiResponseSalonResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseSalonResponse build() => _build();

  _$ApiResponseSalonResponse _build() {
    _$ApiResponseSalonResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseSalonResponse._(
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
            r'ApiResponseSalonResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
