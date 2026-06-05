// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_schedule_override_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseScheduleOverrideResponse
    extends ApiResponseScheduleOverrideResponse {
  @override
  final bool? success;
  @override
  final ScheduleOverrideResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseScheduleOverrideResponse(
          [void Function(ApiResponseScheduleOverrideResponseBuilder)?
              updates]) =>
      (ApiResponseScheduleOverrideResponseBuilder()..update(updates))._build();

  _$ApiResponseScheduleOverrideResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseScheduleOverrideResponse rebuild(
          void Function(ApiResponseScheduleOverrideResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseScheduleOverrideResponseBuilder toBuilder() =>
      ApiResponseScheduleOverrideResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseScheduleOverrideResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseScheduleOverrideResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseScheduleOverrideResponseBuilder
    implements
        Builder<ApiResponseScheduleOverrideResponse,
            ApiResponseScheduleOverrideResponseBuilder> {
  _$ApiResponseScheduleOverrideResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ScheduleOverrideResponseBuilder? _data;
  ScheduleOverrideResponseBuilder get data =>
      _$this._data ??= ScheduleOverrideResponseBuilder();
  set data(ScheduleOverrideResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseScheduleOverrideResponseBuilder() {
    ApiResponseScheduleOverrideResponse._defaults(this);
  }

  ApiResponseScheduleOverrideResponseBuilder get _$this {
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
  void replace(ApiResponseScheduleOverrideResponse other) {
    _$v = other as _$ApiResponseScheduleOverrideResponse;
  }

  @override
  void update(
      void Function(ApiResponseScheduleOverrideResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseScheduleOverrideResponse build() => _build();

  _$ApiResponseScheduleOverrideResponse _build() {
    _$ApiResponseScheduleOverrideResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseScheduleOverrideResponse._(
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
        throw BuiltValueNestedFieldError(r'ApiResponseScheduleOverrideResponse',
            _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
