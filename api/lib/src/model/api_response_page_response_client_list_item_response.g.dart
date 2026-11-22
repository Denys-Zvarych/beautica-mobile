// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_client_list_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseClientListItemResponse
    extends ApiResponsePageResponseClientListItemResponse {
  @override
  final bool? success;
  @override
  final PageResponseClientListItemResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;
  @override
  final String? requestId;

  factory _$ApiResponsePageResponseClientListItemResponse(
          [void Function(ApiResponsePageResponseClientListItemResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseClientListItemResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseClientListItemResponse._(
      {this.success, this.data, this.message, this.errors, this.requestId})
      : super._();
  @override
  ApiResponsePageResponseClientListItemResponse rebuild(
          void Function(ApiResponsePageResponseClientListItemResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseClientListItemResponseBuilder toBuilder() =>
      ApiResponsePageResponseClientListItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseClientListItemResponse &&
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
            r'ApiResponsePageResponseClientListItemResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors)
          ..add('requestId', requestId))
        .toString();
  }
}

class ApiResponsePageResponseClientListItemResponseBuilder
    implements
        Builder<ApiResponsePageResponseClientListItemResponse,
            ApiResponsePageResponseClientListItemResponseBuilder> {
  _$ApiResponsePageResponseClientListItemResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseClientListItemResponseBuilder? _data;
  PageResponseClientListItemResponseBuilder get data =>
      _$this._data ??= PageResponseClientListItemResponseBuilder();
  set data(PageResponseClientListItemResponseBuilder? data) =>
      _$this._data = data;

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

  ApiResponsePageResponseClientListItemResponseBuilder() {
    ApiResponsePageResponseClientListItemResponse._defaults(this);
  }

  ApiResponsePageResponseClientListItemResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseClientListItemResponse other) {
    _$v = other as _$ApiResponsePageResponseClientListItemResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseClientListItemResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseClientListItemResponse build() => _build();

  _$ApiResponsePageResponseClientListItemResponse _build() {
    _$ApiResponsePageResponseClientListItemResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseClientListItemResponse._(
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
            r'ApiResponsePageResponseClientListItemResponse',
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
