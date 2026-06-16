// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_booking_detail_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseBookingDetailResponse
    extends ApiResponseBookingDetailResponse {
  @override
  final bool? success;
  @override
  final BookingDetailResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseBookingDetailResponse(
          [void Function(ApiResponseBookingDetailResponseBuilder)? updates]) =>
      (ApiResponseBookingDetailResponseBuilder()..update(updates))._build();

  _$ApiResponseBookingDetailResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseBookingDetailResponse rebuild(
          void Function(ApiResponseBookingDetailResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseBookingDetailResponseBuilder toBuilder() =>
      ApiResponseBookingDetailResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseBookingDetailResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseBookingDetailResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseBookingDetailResponseBuilder
    implements
        Builder<ApiResponseBookingDetailResponse,
            ApiResponseBookingDetailResponseBuilder> {
  _$ApiResponseBookingDetailResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  BookingDetailResponseBuilder? _data;
  BookingDetailResponseBuilder get data =>
      _$this._data ??= BookingDetailResponseBuilder();
  set data(BookingDetailResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseBookingDetailResponseBuilder() {
    ApiResponseBookingDetailResponse._defaults(this);
  }

  ApiResponseBookingDetailResponseBuilder get _$this {
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
  void replace(ApiResponseBookingDetailResponse other) {
    _$v = other as _$ApiResponseBookingDetailResponse;
  }

  @override
  void update(void Function(ApiResponseBookingDetailResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseBookingDetailResponse build() => _build();

  _$ApiResponseBookingDetailResponse _build() {
    _$ApiResponseBookingDetailResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseBookingDetailResponse._(
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
            r'ApiResponseBookingDetailResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
