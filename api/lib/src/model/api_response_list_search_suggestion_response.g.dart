// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_search_suggestion_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListSearchSuggestionResponse
    extends ApiResponseListSearchSuggestionResponse {
  @override
  final bool? success;
  @override
  final BuiltList<SearchSuggestionResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListSearchSuggestionResponse(
          [void Function(ApiResponseListSearchSuggestionResponseBuilder)?
              updates]) =>
      (ApiResponseListSearchSuggestionResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListSearchSuggestionResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListSearchSuggestionResponse rebuild(
          void Function(ApiResponseListSearchSuggestionResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListSearchSuggestionResponseBuilder toBuilder() =>
      ApiResponseListSearchSuggestionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListSearchSuggestionResponse &&
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
            r'ApiResponseListSearchSuggestionResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListSearchSuggestionResponseBuilder
    implements
        Builder<ApiResponseListSearchSuggestionResponse,
            ApiResponseListSearchSuggestionResponseBuilder> {
  _$ApiResponseListSearchSuggestionResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<SearchSuggestionResponse>? _data;
  ListBuilder<SearchSuggestionResponse> get data =>
      _$this._data ??= ListBuilder<SearchSuggestionResponse>();
  set data(ListBuilder<SearchSuggestionResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListSearchSuggestionResponseBuilder() {
    ApiResponseListSearchSuggestionResponse._defaults(this);
  }

  ApiResponseListSearchSuggestionResponseBuilder get _$this {
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
  void replace(ApiResponseListSearchSuggestionResponse other) {
    _$v = other as _$ApiResponseListSearchSuggestionResponse;
  }

  @override
  void update(
      void Function(ApiResponseListSearchSuggestionResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListSearchSuggestionResponse build() => _build();

  _$ApiResponseListSearchSuggestionResponse _build() {
    _$ApiResponseListSearchSuggestionResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListSearchSuggestionResponse._(
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
            r'ApiResponseListSearchSuggestionResponse',
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
