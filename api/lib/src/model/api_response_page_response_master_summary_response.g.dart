// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_master_summary_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseMasterSummaryResponse
    extends ApiResponsePageResponseMasterSummaryResponse {
  @override
  final bool? success;
  @override
  final PageResponseMasterSummaryResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseMasterSummaryResponse(
          [void Function(ApiResponsePageResponseMasterSummaryResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseMasterSummaryResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseMasterSummaryResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseMasterSummaryResponse rebuild(
          void Function(ApiResponsePageResponseMasterSummaryResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseMasterSummaryResponseBuilder toBuilder() =>
      ApiResponsePageResponseMasterSummaryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseMasterSummaryResponse &&
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
            r'ApiResponsePageResponseMasterSummaryResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseMasterSummaryResponseBuilder
    implements
        Builder<ApiResponsePageResponseMasterSummaryResponse,
            ApiResponsePageResponseMasterSummaryResponseBuilder> {
  _$ApiResponsePageResponseMasterSummaryResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseMasterSummaryResponseBuilder? _data;
  PageResponseMasterSummaryResponseBuilder get data =>
      _$this._data ??= PageResponseMasterSummaryResponseBuilder();
  set data(PageResponseMasterSummaryResponseBuilder? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseMasterSummaryResponseBuilder() {
    ApiResponsePageResponseMasterSummaryResponse._defaults(this);
  }

  ApiResponsePageResponseMasterSummaryResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseMasterSummaryResponse other) {
    _$v = other as _$ApiResponsePageResponseMasterSummaryResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseMasterSummaryResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseMasterSummaryResponse build() => _build();

  _$ApiResponsePageResponseMasterSummaryResponse _build() {
    _$ApiResponsePageResponseMasterSummaryResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseMasterSummaryResponse._(
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
            r'ApiResponsePageResponseMasterSummaryResponse',
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
