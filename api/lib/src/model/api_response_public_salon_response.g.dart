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
  @override
  final BuiltMap<String, String>? errors;
  @override
  final String? requestId;

  factory _$ApiResponsePublicSalonResponse(
          [void Function(ApiResponsePublicSalonResponseBuilder)? updates]) =>
      (ApiResponsePublicSalonResponseBuilder()..update(updates))._build();

  _$ApiResponsePublicSalonResponse._(
      {this.success, this.data, this.message, this.errors, this.requestId})
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
        message == other.message &&
        errors == other.errors &&
        requestId == other.requestId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, errors.hashCode);
    _$hash = $jc(_$hash, requestId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApiResponsePublicSalonResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors)
          ..add('requestId', requestId))
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

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  String? _requestId;
  String? get requestId => _$this._requestId;
  set requestId(String? requestId) => _$this._requestId = requestId;

  ApiResponsePublicSalonResponseBuilder() {
    ApiResponsePublicSalonResponse._defaults(this);
  }

  ApiResponsePublicSalonResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data?.toBuilder();
      _message = $v.message;
      _errors = $v.errors?.toBuilder();
      _requestId = $v.requestId;
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
            errors: _errors?.build(),
            requestId: requestId,
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
            r'ApiResponsePublicSalonResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
