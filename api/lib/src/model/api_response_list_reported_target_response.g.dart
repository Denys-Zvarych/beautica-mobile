// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_reported_target_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListReportedTargetResponse
    extends ApiResponseListReportedTargetResponse {
  @override
  final bool? success;
  @override
  final BuiltList<ReportedTargetResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;
  @override
  final String? requestId;

  factory _$ApiResponseListReportedTargetResponse(
          [void Function(ApiResponseListReportedTargetResponseBuilder)?
              updates]) =>
      (ApiResponseListReportedTargetResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListReportedTargetResponse._(
      {this.success, this.data, this.message, this.errors, this.requestId})
      : super._();
  @override
  ApiResponseListReportedTargetResponse rebuild(
          void Function(ApiResponseListReportedTargetResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListReportedTargetResponseBuilder toBuilder() =>
      ApiResponseListReportedTargetResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListReportedTargetResponse &&
        success == other.success &&
        data == other.data &&
        message == other.message &&
        errors == other.errors &&
        requestId == other.requestId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, errors.hashCode);
    _$hash = $jc(_$hash, requestId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
            r'ApiResponseListReportedTargetResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors)
          ..add('requestId', requestId))
        .toString();
  }
}

class ApiResponseListReportedTargetResponseBuilder
    implements
        Builder<ApiResponseListReportedTargetResponse,
            ApiResponseListReportedTargetResponseBuilder> {
  _$ApiResponseListReportedTargetResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<ReportedTargetResponse>? _data;
  ListBuilder<ReportedTargetResponse> get data =>
      _$this._data ??= ListBuilder<ReportedTargetResponse>();
  set data(ListBuilder<ReportedTargetResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  String? _requestId;
  String? get requestId => _$this._requestId;
  set requestId(String? requestId) => _$this._requestId = requestId;

  ApiResponseListReportedTargetResponseBuilder() {
    ApiResponseListReportedTargetResponse._defaults(this);
  }

  ApiResponseListReportedTargetResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data?.toBuilder();
      _message = $v.message;
      _errors = $v.errors?.toBuilder();
      _requestId = $v.requestId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiResponseListReportedTargetResponse other) {
    _$v = other as _$ApiResponseListReportedTargetResponse;
  }

  @override
  void update(
      void Function(ApiResponseListReportedTargetResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListReportedTargetResponse build() => _build();

  _$ApiResponseListReportedTargetResponse _build() {
    _$ApiResponseListReportedTargetResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListReportedTargetResponse._(
            success: success,
            data: _data?.build(),
            message: message,
            errors: _errors?.build(),
            requestId: requestId,
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
            r'ApiResponseListReportedTargetResponse',
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
