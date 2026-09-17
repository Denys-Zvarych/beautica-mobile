// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_salon_master_effective_schedule_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListSalonMasterEffectiveScheduleResponse
    extends ApiResponseListSalonMasterEffectiveScheduleResponse {
  @override
  final bool? success;
  @override
  final BuiltList<SalonMasterEffectiveScheduleResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListSalonMasterEffectiveScheduleResponse(
          [void Function(
                  ApiResponseListSalonMasterEffectiveScheduleResponseBuilder)?
              updates]) =>
      (ApiResponseListSalonMasterEffectiveScheduleResponseBuilder()
            ..update(updates))
          ._build();

  _$ApiResponseListSalonMasterEffectiveScheduleResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListSalonMasterEffectiveScheduleResponse rebuild(
          void Function(
                  ApiResponseListSalonMasterEffectiveScheduleResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListSalonMasterEffectiveScheduleResponseBuilder toBuilder() =>
      ApiResponseListSalonMasterEffectiveScheduleResponseBuilder()
        ..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListSalonMasterEffectiveScheduleResponse &&
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
            r'ApiResponseListSalonMasterEffectiveScheduleResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListSalonMasterEffectiveScheduleResponseBuilder
    implements
        Builder<ApiResponseListSalonMasterEffectiveScheduleResponse,
            ApiResponseListSalonMasterEffectiveScheduleResponseBuilder> {
  _$ApiResponseListSalonMasterEffectiveScheduleResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<SalonMasterEffectiveScheduleResponse>? _data;
  ListBuilder<SalonMasterEffectiveScheduleResponse> get data =>
      _$this._data ??= ListBuilder<SalonMasterEffectiveScheduleResponse>();
  set data(ListBuilder<SalonMasterEffectiveScheduleResponse>? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListSalonMasterEffectiveScheduleResponseBuilder() {
    ApiResponseListSalonMasterEffectiveScheduleResponse._defaults(this);
  }

  ApiResponseListSalonMasterEffectiveScheduleResponseBuilder get _$this {
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
  void replace(ApiResponseListSalonMasterEffectiveScheduleResponse other) {
    _$v = other as _$ApiResponseListSalonMasterEffectiveScheduleResponse;
  }

  @override
  void update(
      void Function(ApiResponseListSalonMasterEffectiveScheduleResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListSalonMasterEffectiveScheduleResponse build() => _build();

  _$ApiResponseListSalonMasterEffectiveScheduleResponse _build() {
    _$ApiResponseListSalonMasterEffectiveScheduleResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListSalonMasterEffectiveScheduleResponse._(
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
            r'ApiResponseListSalonMasterEffectiveScheduleResponse',
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
