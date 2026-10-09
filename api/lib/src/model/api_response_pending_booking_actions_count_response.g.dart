// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_pending_booking_actions_count_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePendingBookingActionsCountResponse
    extends ApiResponsePendingBookingActionsCountResponse {
  @override
  final bool? success;
  @override
  final PendingBookingActionsCountResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePendingBookingActionsCountResponse(
          [void Function(ApiResponsePendingBookingActionsCountResponseBuilder)?
              updates]) =>
      (ApiResponsePendingBookingActionsCountResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePendingBookingActionsCountResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePendingBookingActionsCountResponse rebuild(
          void Function(ApiResponsePendingBookingActionsCountResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePendingBookingActionsCountResponseBuilder toBuilder() =>
      ApiResponsePendingBookingActionsCountResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePendingBookingActionsCountResponse &&
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
            r'ApiResponsePendingBookingActionsCountResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePendingBookingActionsCountResponseBuilder
    implements
        Builder<ApiResponsePendingBookingActionsCountResponse,
            ApiResponsePendingBookingActionsCountResponseBuilder> {
  _$ApiResponsePendingBookingActionsCountResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PendingBookingActionsCountResponseBuilder? _data;
  PendingBookingActionsCountResponseBuilder get data =>
      _$this._data ??= PendingBookingActionsCountResponseBuilder();
  set data(PendingBookingActionsCountResponseBuilder? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePendingBookingActionsCountResponseBuilder() {
    ApiResponsePendingBookingActionsCountResponse._defaults(this);
  }

  ApiResponsePendingBookingActionsCountResponseBuilder get _$this {
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
  void replace(ApiResponsePendingBookingActionsCountResponse other) {
    _$v = other as _$ApiResponsePendingBookingActionsCountResponse;
  }

  @override
  void update(
      void Function(ApiResponsePendingBookingActionsCountResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePendingBookingActionsCountResponse build() => _build();

  _$ApiResponsePendingBookingActionsCountResponse _build() {
    _$ApiResponsePendingBookingActionsCountResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePendingBookingActionsCountResponse._(
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
            r'ApiResponsePendingBookingActionsCountResponse',
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
