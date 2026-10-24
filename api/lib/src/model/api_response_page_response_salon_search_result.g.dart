// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_salon_search_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseSalonSearchResult
    extends ApiResponsePageResponseSalonSearchResult {
  @override
  final bool? success;
  @override
  final PageResponseSalonSearchResult? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;
  @override
  final String? requestId;

  factory _$ApiResponsePageResponseSalonSearchResult(
          [void Function(ApiResponsePageResponseSalonSearchResultBuilder)?
              updates]) =>
      (ApiResponsePageResponseSalonSearchResultBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseSalonSearchResult._(
      {this.success, this.data, this.message, this.errors, this.requestId})
      : super._();
  @override
  ApiResponsePageResponseSalonSearchResult rebuild(
          void Function(ApiResponsePageResponseSalonSearchResultBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseSalonSearchResultBuilder toBuilder() =>
      ApiResponsePageResponseSalonSearchResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseSalonSearchResult &&
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
            r'ApiResponsePageResponseSalonSearchResult')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors)
          ..add('requestId', requestId))
        .toString();
  }
}

class ApiResponsePageResponseSalonSearchResultBuilder
    implements
        Builder<ApiResponsePageResponseSalonSearchResult,
            ApiResponsePageResponseSalonSearchResultBuilder> {
  _$ApiResponsePageResponseSalonSearchResult? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseSalonSearchResultBuilder? _data;
  PageResponseSalonSearchResultBuilder get data =>
      _$this._data ??= PageResponseSalonSearchResultBuilder();
  set data(PageResponseSalonSearchResultBuilder? data) => _$this._data = data;

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

  ApiResponsePageResponseSalonSearchResultBuilder() {
    ApiResponsePageResponseSalonSearchResult._defaults(this);
  }

  ApiResponsePageResponseSalonSearchResultBuilder get _$this {
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
  void replace(ApiResponsePageResponseSalonSearchResult other) {
    _$v = other as _$ApiResponsePageResponseSalonSearchResult;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseSalonSearchResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseSalonSearchResult build() => _build();

  _$ApiResponsePageResponseSalonSearchResult _build() {
    _$ApiResponsePageResponseSalonSearchResult _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseSalonSearchResult._(
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
            r'ApiResponsePageResponseSalonSearchResult',
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
