// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_booking_links_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseBookingLinksResponse
    extends ApiResponseBookingLinksResponse {
  @override
  final bool? success;
  @override
  final BookingLinksResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;
  @override
  final String? requestId;

  factory _$ApiResponseBookingLinksResponse(
          [void Function(ApiResponseBookingLinksResponseBuilder)? updates]) =>
      (ApiResponseBookingLinksResponseBuilder()..update(updates))._build();

  _$ApiResponseBookingLinksResponse._(
      {this.success, this.data, this.message, this.errors, this.requestId})
      : super._();
  @override
  ApiResponseBookingLinksResponse rebuild(
          void Function(ApiResponseBookingLinksResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseBookingLinksResponseBuilder toBuilder() =>
      ApiResponseBookingLinksResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseBookingLinksResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseBookingLinksResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors)
          ..add('requestId', requestId))
        .toString();
  }
}

class ApiResponseBookingLinksResponseBuilder
    implements
        Builder<ApiResponseBookingLinksResponse,
            ApiResponseBookingLinksResponseBuilder> {
  _$ApiResponseBookingLinksResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  BookingLinksResponseBuilder? _data;
  BookingLinksResponseBuilder get data =>
      _$this._data ??= BookingLinksResponseBuilder();
  set data(BookingLinksResponseBuilder? data) => _$this._data = data;

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

  ApiResponseBookingLinksResponseBuilder() {
    ApiResponseBookingLinksResponse._defaults(this);
  }

  ApiResponseBookingLinksResponseBuilder get _$this {
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
  void replace(ApiResponseBookingLinksResponse other) {
    _$v = other as _$ApiResponseBookingLinksResponse;
  }

  @override
  void update(void Function(ApiResponseBookingLinksResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseBookingLinksResponse build() => _build();

  _$ApiResponseBookingLinksResponse _build() {
    _$ApiResponseBookingLinksResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseBookingLinksResponse._(
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
            r'ApiResponseBookingLinksResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
