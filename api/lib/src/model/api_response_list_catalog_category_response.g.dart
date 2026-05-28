// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_catalog_category_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListCatalogCategoryResponse
    extends ApiResponseListCatalogCategoryResponse {
  @override
  final bool? success;
  @override
  final BuiltList<CatalogCategoryResponse>? data;
  @override
  final String? message;

  factory _$ApiResponseListCatalogCategoryResponse(
          [void Function(ApiResponseListCatalogCategoryResponseBuilder)?
              updates]) =>
      (ApiResponseListCatalogCategoryResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListCatalogCategoryResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseListCatalogCategoryResponse rebuild(
          void Function(ApiResponseListCatalogCategoryResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListCatalogCategoryResponseBuilder toBuilder() =>
      ApiResponseListCatalogCategoryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListCatalogCategoryResponse &&
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
            r'ApiResponseListCatalogCategoryResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseListCatalogCategoryResponseBuilder
    implements
        Builder<ApiResponseListCatalogCategoryResponse,
            ApiResponseListCatalogCategoryResponseBuilder> {
  _$ApiResponseListCatalogCategoryResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<CatalogCategoryResponse>? _data;
  ListBuilder<CatalogCategoryResponse> get data =>
      _$this._data ??= ListBuilder<CatalogCategoryResponse>();
  set data(ListBuilder<CatalogCategoryResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseListCatalogCategoryResponseBuilder() {
    ApiResponseListCatalogCategoryResponse._defaults(this);
  }

  ApiResponseListCatalogCategoryResponseBuilder get _$this {
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
  void replace(ApiResponseListCatalogCategoryResponse other) {
    _$v = other as _$ApiResponseListCatalogCategoryResponse;
  }

  @override
  void update(
      void Function(ApiResponseListCatalogCategoryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListCatalogCategoryResponse build() => _build();

  _$ApiResponseListCatalogCategoryResponse _build() {
    _$ApiResponseListCatalogCategoryResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListCatalogCategoryResponse._(
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
            r'ApiResponseListCatalogCategoryResponse',
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
