// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_my_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseMyReviewResponse
    extends ApiResponsePageResponseMyReviewResponse {
  @override
  final bool? success;
  @override
  final PageResponseMyReviewResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseMyReviewResponse(
          [void Function(ApiResponsePageResponseMyReviewResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseMyReviewResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseMyReviewResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseMyReviewResponse rebuild(
          void Function(ApiResponsePageResponseMyReviewResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseMyReviewResponseBuilder toBuilder() =>
      ApiResponsePageResponseMyReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseMyReviewResponse &&
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
            r'ApiResponsePageResponseMyReviewResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseMyReviewResponseBuilder
    implements
        Builder<ApiResponsePageResponseMyReviewResponse,
            ApiResponsePageResponseMyReviewResponseBuilder> {
  _$ApiResponsePageResponseMyReviewResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseMyReviewResponseBuilder? _data;
  PageResponseMyReviewResponseBuilder get data =>
      _$this._data ??= PageResponseMyReviewResponseBuilder();
  set data(PageResponseMyReviewResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseMyReviewResponseBuilder() {
    ApiResponsePageResponseMyReviewResponse._defaults(this);
  }

  ApiResponsePageResponseMyReviewResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseMyReviewResponse other) {
    _$v = other as _$ApiResponsePageResponseMyReviewResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseMyReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseMyReviewResponse build() => _build();

  _$ApiResponsePageResponseMyReviewResponse _build() {
    _$ApiResponsePageResponseMyReviewResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseMyReviewResponse._(
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
            r'ApiResponsePageResponseMyReviewResponse',
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
