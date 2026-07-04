// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_master_working_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListMasterWorkingDayResponse
    extends ApiResponseListMasterWorkingDayResponse {
  @override
  final bool? success;
  @override
  final BuiltList<MasterWorkingDayResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListMasterWorkingDayResponse(
          [void Function(ApiResponseListMasterWorkingDayResponseBuilder)?
              updates]) =>
      (ApiResponseListMasterWorkingDayResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListMasterWorkingDayResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListMasterWorkingDayResponse rebuild(
          void Function(ApiResponseListMasterWorkingDayResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListMasterWorkingDayResponseBuilder toBuilder() =>
      ApiResponseListMasterWorkingDayResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListMasterWorkingDayResponse &&
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
            r'ApiResponseListMasterWorkingDayResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListMasterWorkingDayResponseBuilder
    implements
        Builder<ApiResponseListMasterWorkingDayResponse,
            ApiResponseListMasterWorkingDayResponseBuilder> {
  _$ApiResponseListMasterWorkingDayResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<MasterWorkingDayResponse>? _data;
  ListBuilder<MasterWorkingDayResponse> get data =>
      _$this._data ??= ListBuilder<MasterWorkingDayResponse>();
  set data(ListBuilder<MasterWorkingDayResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListMasterWorkingDayResponseBuilder() {
    ApiResponseListMasterWorkingDayResponse._defaults(this);
  }

  ApiResponseListMasterWorkingDayResponseBuilder get _$this {
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
  void replace(ApiResponseListMasterWorkingDayResponse other) {
    _$v = other as _$ApiResponseListMasterWorkingDayResponse;
  }

  @override
  void update(
      void Function(ApiResponseListMasterWorkingDayResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListMasterWorkingDayResponse build() => _build();

  _$ApiResponseListMasterWorkingDayResponse _build() {
    _$ApiResponseListMasterWorkingDayResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListMasterWorkingDayResponse._(
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
            r'ApiResponseListMasterWorkingDayResponse',
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
