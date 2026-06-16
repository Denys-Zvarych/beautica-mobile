// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_working_hours_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListWorkingHoursResponse
    extends ApiResponseListWorkingHoursResponse {
  @override
  final bool? success;
  @override
  final BuiltList<WorkingHoursResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListWorkingHoursResponse(
          [void Function(ApiResponseListWorkingHoursResponseBuilder)?
              updates]) =>
      (ApiResponseListWorkingHoursResponseBuilder()..update(updates))._build();

  _$ApiResponseListWorkingHoursResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListWorkingHoursResponse rebuild(
          void Function(ApiResponseListWorkingHoursResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListWorkingHoursResponseBuilder toBuilder() =>
      ApiResponseListWorkingHoursResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListWorkingHoursResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListWorkingHoursResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListWorkingHoursResponseBuilder
    implements
        Builder<ApiResponseListWorkingHoursResponse,
            ApiResponseListWorkingHoursResponseBuilder> {
  _$ApiResponseListWorkingHoursResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<WorkingHoursResponse>? _data;
  ListBuilder<WorkingHoursResponse> get data =>
      _$this._data ??= ListBuilder<WorkingHoursResponse>();
  set data(ListBuilder<WorkingHoursResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListWorkingHoursResponseBuilder() {
    ApiResponseListWorkingHoursResponse._defaults(this);
  }

  ApiResponseListWorkingHoursResponseBuilder get _$this {
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
  void replace(ApiResponseListWorkingHoursResponse other) {
    _$v = other as _$ApiResponseListWorkingHoursResponse;
  }

  @override
  void update(
      void Function(ApiResponseListWorkingHoursResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListWorkingHoursResponse build() => _build();

  _$ApiResponseListWorkingHoursResponse _build() {
    _$ApiResponseListWorkingHoursResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListWorkingHoursResponse._(
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
        throw BuiltValueNestedFieldError(r'ApiResponseListWorkingHoursResponse',
            _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
