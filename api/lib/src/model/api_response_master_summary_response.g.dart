// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_master_summary_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseMasterSummaryResponse
    extends ApiResponseMasterSummaryResponse {
  @override
  final bool? success;
  @override
  final MasterSummaryResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseMasterSummaryResponse(
          [void Function(ApiResponseMasterSummaryResponseBuilder)? updates]) =>
      (ApiResponseMasterSummaryResponseBuilder()..update(updates))._build();

  _$ApiResponseMasterSummaryResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseMasterSummaryResponse rebuild(
          void Function(ApiResponseMasterSummaryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseMasterSummaryResponseBuilder toBuilder() =>
      ApiResponseMasterSummaryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseMasterSummaryResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseMasterSummaryResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseMasterSummaryResponseBuilder
    implements
        Builder<ApiResponseMasterSummaryResponse,
            ApiResponseMasterSummaryResponseBuilder> {
  _$ApiResponseMasterSummaryResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  MasterSummaryResponseBuilder? _data;
  MasterSummaryResponseBuilder get data =>
      _$this._data ??= MasterSummaryResponseBuilder();
  set data(MasterSummaryResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseMasterSummaryResponseBuilder() {
    ApiResponseMasterSummaryResponse._defaults(this);
  }

  ApiResponseMasterSummaryResponseBuilder get _$this {
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
  void replace(ApiResponseMasterSummaryResponse other) {
    _$v = other as _$ApiResponseMasterSummaryResponse;
  }

  @override
  void update(void Function(ApiResponseMasterSummaryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseMasterSummaryResponse build() => _build();

  _$ApiResponseMasterSummaryResponse _build() {
    _$ApiResponseMasterSummaryResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseMasterSummaryResponse._(
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
            r'ApiResponseMasterSummaryResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
