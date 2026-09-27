// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_settlement_search_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListSettlementSearchResponse
    extends ApiResponseListSettlementSearchResponse {
  @override
  final bool? success;
  @override
  final BuiltList<SettlementSearchResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListSettlementSearchResponse(
          [void Function(ApiResponseListSettlementSearchResponseBuilder)?
              updates]) =>
      (ApiResponseListSettlementSearchResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseListSettlementSearchResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListSettlementSearchResponse rebuild(
          void Function(ApiResponseListSettlementSearchResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListSettlementSearchResponseBuilder toBuilder() =>
      ApiResponseListSettlementSearchResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListSettlementSearchResponse &&
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
            r'ApiResponseListSettlementSearchResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListSettlementSearchResponseBuilder
    implements
        Builder<ApiResponseListSettlementSearchResponse,
            ApiResponseListSettlementSearchResponseBuilder> {
  _$ApiResponseListSettlementSearchResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<SettlementSearchResponse>? _data;
  ListBuilder<SettlementSearchResponse> get data =>
      _$this._data ??= ListBuilder<SettlementSearchResponse>();
  set data(ListBuilder<SettlementSearchResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListSettlementSearchResponseBuilder() {
    ApiResponseListSettlementSearchResponse._defaults(this);
  }

  ApiResponseListSettlementSearchResponseBuilder get _$this {
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
  void replace(ApiResponseListSettlementSearchResponse other) {
    _$v = other as _$ApiResponseListSettlementSearchResponse;
  }

  @override
  void update(
      void Function(ApiResponseListSettlementSearchResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListSettlementSearchResponse build() => _build();

  _$ApiResponseListSettlementSearchResponse _build() {
    _$ApiResponseListSettlementSearchResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListSettlementSearchResponse._(
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
            r'ApiResponseListSettlementSearchResponse',
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
