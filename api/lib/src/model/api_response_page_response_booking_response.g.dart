// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_booking_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseBookingResponse
    extends ApiResponsePageResponseBookingResponse {
  @override
  final bool? success;
  @override
  final PageResponseBookingResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseBookingResponse(
          [void Function(ApiResponsePageResponseBookingResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseBookingResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseBookingResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseBookingResponse rebuild(
          void Function(ApiResponsePageResponseBookingResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseBookingResponseBuilder toBuilder() =>
      ApiResponsePageResponseBookingResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseBookingResponse &&
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
            r'ApiResponsePageResponseBookingResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseBookingResponseBuilder
    implements
        Builder<ApiResponsePageResponseBookingResponse,
            ApiResponsePageResponseBookingResponseBuilder> {
  _$ApiResponsePageResponseBookingResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseBookingResponseBuilder? _data;
  PageResponseBookingResponseBuilder get data =>
      _$this._data ??= PageResponseBookingResponseBuilder();
  set data(PageResponseBookingResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseBookingResponseBuilder() {
    ApiResponsePageResponseBookingResponse._defaults(this);
  }

  ApiResponsePageResponseBookingResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseBookingResponse other) {
    _$v = other as _$ApiResponsePageResponseBookingResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseBookingResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseBookingResponse build() => _build();

  _$ApiResponsePageResponseBookingResponse _build() {
    _$ApiResponsePageResponseBookingResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseBookingResponse._(
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
            r'ApiResponsePageResponseBookingResponse',
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
