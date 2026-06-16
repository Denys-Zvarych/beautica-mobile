// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_available_slots_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseAvailableSlotsResponse
    extends ApiResponseAvailableSlotsResponse {
  @override
  final bool? success;
  @override
  final AvailableSlotsResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseAvailableSlotsResponse(
          [void Function(ApiResponseAvailableSlotsResponseBuilder)? updates]) =>
      (ApiResponseAvailableSlotsResponseBuilder()..update(updates))._build();

  _$ApiResponseAvailableSlotsResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseAvailableSlotsResponse rebuild(
          void Function(ApiResponseAvailableSlotsResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseAvailableSlotsResponseBuilder toBuilder() =>
      ApiResponseAvailableSlotsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseAvailableSlotsResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseAvailableSlotsResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseAvailableSlotsResponseBuilder
    implements
        Builder<ApiResponseAvailableSlotsResponse,
            ApiResponseAvailableSlotsResponseBuilder> {
  _$ApiResponseAvailableSlotsResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  AvailableSlotsResponseBuilder? _data;
  AvailableSlotsResponseBuilder get data =>
      _$this._data ??= AvailableSlotsResponseBuilder();
  set data(AvailableSlotsResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseAvailableSlotsResponseBuilder() {
    ApiResponseAvailableSlotsResponse._defaults(this);
  }

  ApiResponseAvailableSlotsResponseBuilder get _$this {
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
  void replace(ApiResponseAvailableSlotsResponse other) {
    _$v = other as _$ApiResponseAvailableSlotsResponse;
  }

  @override
  void update(
      void Function(ApiResponseAvailableSlotsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseAvailableSlotsResponse build() => _build();

  _$ApiResponseAvailableSlotsResponse _build() {
    _$ApiResponseAvailableSlotsResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseAvailableSlotsResponse._(
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
            r'ApiResponseAvailableSlotsResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
