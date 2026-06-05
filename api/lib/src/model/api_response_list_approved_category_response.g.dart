// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_approved_category_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListApprovedCategoryResponse
    extends ApiResponseListApprovedCategoryResponse {
  @override
  final bool? success;
  @override
  final BuiltList<ApprovedCategoryResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListApprovedCategoryResponse(
          [void Function(ApiResponseListApprovedCategoryResponseBuilder)?
              updates]) =>
      (ApiResponseListApprovedCategoryResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListApprovedCategoryResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListApprovedCategoryResponse rebuild(
          void Function(ApiResponseListApprovedCategoryResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListApprovedCategoryResponseBuilder toBuilder() =>
      ApiResponseListApprovedCategoryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListApprovedCategoryResponse &&
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
            r'ApiResponseListApprovedCategoryResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListApprovedCategoryResponseBuilder
    implements
        Builder<ApiResponseListApprovedCategoryResponse,
            ApiResponseListApprovedCategoryResponseBuilder> {
  _$ApiResponseListApprovedCategoryResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<ApprovedCategoryResponse>? _data;
  ListBuilder<ApprovedCategoryResponse> get data =>
      _$this._data ??= ListBuilder<ApprovedCategoryResponse>();
  set data(ListBuilder<ApprovedCategoryResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListApprovedCategoryResponseBuilder() {
    ApiResponseListApprovedCategoryResponse._defaults(this);
  }

  ApiResponseListApprovedCategoryResponseBuilder get _$this {
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
  void replace(ApiResponseListApprovedCategoryResponse other) {
    _$v = other as _$ApiResponseListApprovedCategoryResponse;
  }

  @override
  void update(
      void Function(ApiResponseListApprovedCategoryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListApprovedCategoryResponse build() => _build();

  _$ApiResponseListApprovedCategoryResponse _build() {
    _$ApiResponseListApprovedCategoryResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListApprovedCategoryResponse._(
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
            r'ApiResponseListApprovedCategoryResponse',
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
