// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_client_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseClientReviewResponse
    extends ApiResponseClientReviewResponse {
  @override
  final bool? success;
  @override
  final ClientReviewResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseClientReviewResponse(
          [void Function(ApiResponseClientReviewResponseBuilder)? updates]) =>
      (ApiResponseClientReviewResponseBuilder()..update(updates))._build();

  _$ApiResponseClientReviewResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseClientReviewResponse rebuild(
          void Function(ApiResponseClientReviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseClientReviewResponseBuilder toBuilder() =>
      ApiResponseClientReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseClientReviewResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseClientReviewResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseClientReviewResponseBuilder
    implements
        Builder<ApiResponseClientReviewResponse,
            ApiResponseClientReviewResponseBuilder> {
  _$ApiResponseClientReviewResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ClientReviewResponseBuilder? _data;
  ClientReviewResponseBuilder get data =>
      _$this._data ??= ClientReviewResponseBuilder();
  set data(ClientReviewResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseClientReviewResponseBuilder() {
    ApiResponseClientReviewResponse._defaults(this);
  }

  ApiResponseClientReviewResponseBuilder get _$this {
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
  void replace(ApiResponseClientReviewResponse other) {
    _$v = other as _$ApiResponseClientReviewResponse;
  }

  @override
  void update(void Function(ApiResponseClientReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseClientReviewResponse build() => _build();

  _$ApiResponseClientReviewResponse _build() {
    _$ApiResponseClientReviewResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseClientReviewResponse._(
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
            r'ApiResponseClientReviewResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
