// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_master_review_summary_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseMasterReviewSummaryResponse
    extends ApiResponseMasterReviewSummaryResponse {
  @override
  final bool? success;
  @override
  final MasterReviewSummaryResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseMasterReviewSummaryResponse(
          [void Function(ApiResponseMasterReviewSummaryResponseBuilder)?
              updates]) =>
      (ApiResponseMasterReviewSummaryResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseMasterReviewSummaryResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseMasterReviewSummaryResponse rebuild(
          void Function(ApiResponseMasterReviewSummaryResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseMasterReviewSummaryResponseBuilder toBuilder() =>
      ApiResponseMasterReviewSummaryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseMasterReviewSummaryResponse &&
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
            r'ApiResponseMasterReviewSummaryResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseMasterReviewSummaryResponseBuilder
    implements
        Builder<ApiResponseMasterReviewSummaryResponse,
            ApiResponseMasterReviewSummaryResponseBuilder> {
  _$ApiResponseMasterReviewSummaryResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  MasterReviewSummaryResponseBuilder? _data;
  MasterReviewSummaryResponseBuilder get data =>
      _$this._data ??= MasterReviewSummaryResponseBuilder();
  set data(MasterReviewSummaryResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseMasterReviewSummaryResponseBuilder() {
    ApiResponseMasterReviewSummaryResponse._defaults(this);
  }

  ApiResponseMasterReviewSummaryResponseBuilder get _$this {
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
  void replace(ApiResponseMasterReviewSummaryResponse other) {
    _$v = other as _$ApiResponseMasterReviewSummaryResponse;
  }

  @override
  void update(
      void Function(ApiResponseMasterReviewSummaryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseMasterReviewSummaryResponse build() => _build();

  _$ApiResponseMasterReviewSummaryResponse _build() {
    _$ApiResponseMasterReviewSummaryResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseMasterReviewSummaryResponse._(
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
            r'ApiResponseMasterReviewSummaryResponse',
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
