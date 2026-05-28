// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseReviewResponse extends ApiResponseReviewResponse {
  @override
  final bool? success;
  @override
  final ReviewResponse? data;
  @override
  final String? message;

  factory _$ApiResponseReviewResponse(
          [void Function(ApiResponseReviewResponseBuilder)? updates]) =>
      (ApiResponseReviewResponseBuilder()..update(updates))._build();

  _$ApiResponseReviewResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseReviewResponse rebuild(
          void Function(ApiResponseReviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseReviewResponseBuilder toBuilder() =>
      ApiResponseReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseReviewResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseReviewResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseReviewResponseBuilder
    implements
        Builder<ApiResponseReviewResponse, ApiResponseReviewResponseBuilder> {
  _$ApiResponseReviewResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ReviewResponseBuilder? _data;
  ReviewResponseBuilder get data => _$this._data ??= ReviewResponseBuilder();
  set data(ReviewResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseReviewResponseBuilder() {
    ApiResponseReviewResponse._defaults(this);
  }

  ApiResponseReviewResponseBuilder get _$this {
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
  void replace(ApiResponseReviewResponse other) {
    _$v = other as _$ApiResponseReviewResponse;
  }

  @override
  void update(void Function(ApiResponseReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseReviewResponse build() => _build();

  _$ApiResponseReviewResponse _build() {
    _$ApiResponseReviewResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseReviewResponse._(
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
            r'ApiResponseReviewResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
