// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_schedule_override_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListScheduleOverrideResponse
    extends ApiResponseListScheduleOverrideResponse {
  @override
  final bool? success;
  @override
  final BuiltList<ScheduleOverrideResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListScheduleOverrideResponse(
          [void Function(ApiResponseListScheduleOverrideResponseBuilder)?
              updates]) =>
      (ApiResponseListScheduleOverrideResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListScheduleOverrideResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListScheduleOverrideResponse rebuild(
          void Function(ApiResponseListScheduleOverrideResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListScheduleOverrideResponseBuilder toBuilder() =>
      ApiResponseListScheduleOverrideResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListScheduleOverrideResponse &&
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
            r'ApiResponseListScheduleOverrideResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListScheduleOverrideResponseBuilder
    implements
        Builder<ApiResponseListScheduleOverrideResponse,
            ApiResponseListScheduleOverrideResponseBuilder> {
  _$ApiResponseListScheduleOverrideResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<ScheduleOverrideResponse>? _data;
  ListBuilder<ScheduleOverrideResponse> get data =>
      _$this._data ??= ListBuilder<ScheduleOverrideResponse>();
  set data(ListBuilder<ScheduleOverrideResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListScheduleOverrideResponseBuilder() {
    ApiResponseListScheduleOverrideResponse._defaults(this);
  }

  ApiResponseListScheduleOverrideResponseBuilder get _$this {
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
  void replace(ApiResponseListScheduleOverrideResponse other) {
    _$v = other as _$ApiResponseListScheduleOverrideResponse;
  }

  @override
  void update(
      void Function(ApiResponseListScheduleOverrideResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListScheduleOverrideResponse build() => _build();

  _$ApiResponseListScheduleOverrideResponse _build() {
    _$ApiResponseListScheduleOverrideResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListScheduleOverrideResponse._(
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
            r'ApiResponseListScheduleOverrideResponse',
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
