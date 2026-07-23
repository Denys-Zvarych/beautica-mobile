// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_salon_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseSalonReviewResponse
    extends ApiResponsePageResponseSalonReviewResponse {
  @override
  final bool? success;
  @override
  final PageResponseSalonReviewResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseSalonReviewResponse(
          [void Function(ApiResponsePageResponseSalonReviewResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseSalonReviewResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseSalonReviewResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseSalonReviewResponse rebuild(
          void Function(ApiResponsePageResponseSalonReviewResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseSalonReviewResponseBuilder toBuilder() =>
      ApiResponsePageResponseSalonReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseSalonReviewResponse &&
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
            r'ApiResponsePageResponseSalonReviewResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseSalonReviewResponseBuilder
    implements
        Builder<ApiResponsePageResponseSalonReviewResponse,
            ApiResponsePageResponseSalonReviewResponseBuilder> {
  _$ApiResponsePageResponseSalonReviewResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseSalonReviewResponseBuilder? _data;
  PageResponseSalonReviewResponseBuilder get data =>
      _$this._data ??= PageResponseSalonReviewResponseBuilder();
  set data(PageResponseSalonReviewResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseSalonReviewResponseBuilder() {
    ApiResponsePageResponseSalonReviewResponse._defaults(this);
  }

  ApiResponsePageResponseSalonReviewResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseSalonReviewResponse other) {
    _$v = other as _$ApiResponsePageResponseSalonReviewResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseSalonReviewResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseSalonReviewResponse build() => _build();

  _$ApiResponsePageResponseSalonReviewResponse _build() {
    _$ApiResponsePageResponseSalonReviewResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseSalonReviewResponse._(
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
            r'ApiResponsePageResponseSalonReviewResponse',
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
