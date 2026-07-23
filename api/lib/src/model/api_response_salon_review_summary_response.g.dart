// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_salon_review_summary_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseSalonReviewSummaryResponse
    extends ApiResponseSalonReviewSummaryResponse {
  @override
  final bool? success;
  @override
  final SalonReviewSummaryResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseSalonReviewSummaryResponse(
          [void Function(ApiResponseSalonReviewSummaryResponseBuilder)?
              updates]) =>
      (ApiResponseSalonReviewSummaryResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseSalonReviewSummaryResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseSalonReviewSummaryResponse rebuild(
          void Function(ApiResponseSalonReviewSummaryResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseSalonReviewSummaryResponseBuilder toBuilder() =>
      ApiResponseSalonReviewSummaryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseSalonReviewSummaryResponse &&
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
            r'ApiResponseSalonReviewSummaryResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseSalonReviewSummaryResponseBuilder
    implements
        Builder<ApiResponseSalonReviewSummaryResponse,
            ApiResponseSalonReviewSummaryResponseBuilder> {
  _$ApiResponseSalonReviewSummaryResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  SalonReviewSummaryResponseBuilder? _data;
  SalonReviewSummaryResponseBuilder get data =>
      _$this._data ??= SalonReviewSummaryResponseBuilder();
  set data(SalonReviewSummaryResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseSalonReviewSummaryResponseBuilder() {
    ApiResponseSalonReviewSummaryResponse._defaults(this);
  }

  ApiResponseSalonReviewSummaryResponseBuilder get _$this {
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
  void replace(ApiResponseSalonReviewSummaryResponse other) {
    _$v = other as _$ApiResponseSalonReviewSummaryResponse;
  }

  @override
  void update(
      void Function(ApiResponseSalonReviewSummaryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseSalonReviewSummaryResponse build() => _build();

  _$ApiResponseSalonReviewSummaryResponse _build() {
    _$ApiResponseSalonReviewSummaryResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseSalonReviewSummaryResponse._(
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
            r'ApiResponseSalonReviewSummaryResponse',
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
