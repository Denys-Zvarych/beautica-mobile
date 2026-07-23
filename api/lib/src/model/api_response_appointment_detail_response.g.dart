// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_appointment_detail_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseAppointmentDetailResponse
    extends ApiResponseAppointmentDetailResponse {
  @override
  final bool? success;
  @override
  final AppointmentDetailResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseAppointmentDetailResponse(
          [void Function(ApiResponseAppointmentDetailResponseBuilder)?
              updates]) =>
      (ApiResponseAppointmentDetailResponseBuilder()..update(updates))._build();

  _$ApiResponseAppointmentDetailResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseAppointmentDetailResponse rebuild(
          void Function(ApiResponseAppointmentDetailResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseAppointmentDetailResponseBuilder toBuilder() =>
      ApiResponseAppointmentDetailResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseAppointmentDetailResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseAppointmentDetailResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseAppointmentDetailResponseBuilder
    implements
        Builder<ApiResponseAppointmentDetailResponse,
            ApiResponseAppointmentDetailResponseBuilder> {
  _$ApiResponseAppointmentDetailResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  AppointmentDetailResponseBuilder? _data;
  AppointmentDetailResponseBuilder get data =>
      _$this._data ??= AppointmentDetailResponseBuilder();
  set data(AppointmentDetailResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseAppointmentDetailResponseBuilder() {
    ApiResponseAppointmentDetailResponse._defaults(this);
  }

  ApiResponseAppointmentDetailResponseBuilder get _$this {
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
  void replace(ApiResponseAppointmentDetailResponse other) {
    _$v = other as _$ApiResponseAppointmentDetailResponse;
  }

  @override
  void update(
      void Function(ApiResponseAppointmentDetailResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseAppointmentDetailResponse build() => _build();

  _$ApiResponseAppointmentDetailResponse _build() {
    _$ApiResponseAppointmentDetailResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseAppointmentDetailResponse._(
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
            r'ApiResponseAppointmentDetailResponse',
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
