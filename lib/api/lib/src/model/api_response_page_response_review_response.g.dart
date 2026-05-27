// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseReviewResponse
    extends ApiResponsePageResponseReviewResponse {
  @override
  final bool? success;
  @override
  final PageResponseReviewResponse? data;
  @override
  final String? message;

  factory _$ApiResponsePageResponseReviewResponse(
          [void Function(ApiResponsePageResponseReviewResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseReviewResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseReviewResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ApiResponsePageResponseReviewResponse rebuild(
          void Function(ApiResponsePageResponseReviewResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseReviewResponseBuilder toBuilder() =>
      ApiResponsePageResponseReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseReviewResponse &&
        success == other.success &&
        data == other.data &&
        message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
            r'ApiResponsePageResponseReviewResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponsePageResponseReviewResponseBuilder
    implements
        Builder<ApiResponsePageResponseReviewResponse,
            ApiResponsePageResponseReviewResponseBuilder> {
  _$ApiResponsePageResponseReviewResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseReviewResponseBuilder? _data;
  PageResponseReviewResponseBuilder get data =>
      _$this._data ??= PageResponseReviewResponseBuilder();
  set data(PageResponseReviewResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponsePageResponseReviewResponseBuilder() {
    ApiResponsePageResponseReviewResponse._defaults(this);
  }

  ApiResponsePageResponseReviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _success = $v.success;
      _data = $v.data?.toBuilder();
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiResponsePageResponseReviewResponse other) {
    _$v = other as _$ApiResponsePageResponseReviewResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseReviewResponse build() => _build();

  _$ApiResponsePageResponseReviewResponse _build() {
    _$ApiResponsePageResponseReviewResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseReviewResponse._(
            success: success,
            data: _data?.build(),
            message: message,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        _data?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApiResponsePageResponseReviewResponse',
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
