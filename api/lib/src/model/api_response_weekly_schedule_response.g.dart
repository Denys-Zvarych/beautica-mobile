// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_weekly_schedule_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseWeeklyScheduleResponse
    extends ApiResponseWeeklyScheduleResponse {
  @override
  final bool? success;
  @override
  final WeeklyScheduleResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseWeeklyScheduleResponse(
          [void Function(ApiResponseWeeklyScheduleResponseBuilder)? updates]) =>
      (ApiResponseWeeklyScheduleResponseBuilder()..update(updates))._build();

  _$ApiResponseWeeklyScheduleResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseWeeklyScheduleResponse rebuild(
          void Function(ApiResponseWeeklyScheduleResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseWeeklyScheduleResponseBuilder toBuilder() =>
      ApiResponseWeeklyScheduleResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseWeeklyScheduleResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseWeeklyScheduleResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseWeeklyScheduleResponseBuilder
    implements
        Builder<ApiResponseWeeklyScheduleResponse,
            ApiResponseWeeklyScheduleResponseBuilder> {
  _$ApiResponseWeeklyScheduleResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  WeeklyScheduleResponseBuilder? _data;
  WeeklyScheduleResponseBuilder get data =>
      _$this._data ??= WeeklyScheduleResponseBuilder();
  set data(WeeklyScheduleResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseWeeklyScheduleResponseBuilder() {
    ApiResponseWeeklyScheduleResponse._defaults(this);
  }

  ApiResponseWeeklyScheduleResponseBuilder get _$this {
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
  void replace(ApiResponseWeeklyScheduleResponse other) {
    _$v = other as _$ApiResponseWeeklyScheduleResponse;
  }

  @override
  void update(
      void Function(ApiResponseWeeklyScheduleResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseWeeklyScheduleResponse build() => _build();

  _$ApiResponseWeeklyScheduleResponse _build() {
    _$ApiResponseWeeklyScheduleResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseWeeklyScheduleResponse._(
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
            r'ApiResponseWeeklyScheduleResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
