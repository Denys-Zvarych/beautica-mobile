// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_master_search_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseMasterSearchResult
    extends ApiResponsePageResponseMasterSearchResult {
  @override
  final bool? success;
  @override
  final PageResponseMasterSearchResult? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseMasterSearchResult(
          [void Function(ApiResponsePageResponseMasterSearchResultBuilder)?
              updates]) =>
      (ApiResponsePageResponseMasterSearchResultBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseMasterSearchResult._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseMasterSearchResult rebuild(
          void Function(ApiResponsePageResponseMasterSearchResultBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseMasterSearchResultBuilder toBuilder() =>
      ApiResponsePageResponseMasterSearchResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseMasterSearchResult &&
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
            r'ApiResponsePageResponseMasterSearchResult')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseMasterSearchResultBuilder
    implements
        Builder<ApiResponsePageResponseMasterSearchResult,
            ApiResponsePageResponseMasterSearchResultBuilder> {
  _$ApiResponsePageResponseMasterSearchResult? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseMasterSearchResultBuilder? _data;
  PageResponseMasterSearchResultBuilder get data =>
      _$this._data ??= PageResponseMasterSearchResultBuilder();
  set data(PageResponseMasterSearchResultBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseMasterSearchResultBuilder() {
    ApiResponsePageResponseMasterSearchResult._defaults(this);
  }

  ApiResponsePageResponseMasterSearchResultBuilder get _$this {
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
  void replace(ApiResponsePageResponseMasterSearchResult other) {
    _$v = other as _$ApiResponsePageResponseMasterSearchResult;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseMasterSearchResultBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseMasterSearchResult build() => _build();

  _$ApiResponsePageResponseMasterSearchResult _build() {
    _$ApiResponsePageResponseMasterSearchResult _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseMasterSearchResult._(
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
            r'ApiResponsePageResponseMasterSearchResult',
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
