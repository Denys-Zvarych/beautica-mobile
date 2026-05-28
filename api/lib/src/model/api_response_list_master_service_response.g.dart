// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_master_service_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListMasterServiceResponse
    extends ApiResponseListMasterServiceResponse {
  @override
  final bool? success;
  @override
  final BuiltList<MasterServiceResponse>? data;
  @override
  final String? message;

  factory _$ApiResponseListMasterServiceResponse(
          [void Function(ApiResponseListMasterServiceResponseBuilder)?
              updates]) =>
      (ApiResponseListMasterServiceResponseBuilder()..update(updates))._build();

  _$ApiResponseListMasterServiceResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseListMasterServiceResponse rebuild(
          void Function(ApiResponseListMasterServiceResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListMasterServiceResponseBuilder toBuilder() =>
      ApiResponseListMasterServiceResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListMasterServiceResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListMasterServiceResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseListMasterServiceResponseBuilder
    implements
        Builder<ApiResponseListMasterServiceResponse,
            ApiResponseListMasterServiceResponseBuilder> {
  _$ApiResponseListMasterServiceResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<MasterServiceResponse>? _data;
  ListBuilder<MasterServiceResponse> get data =>
      _$this._data ??= ListBuilder<MasterServiceResponse>();
  set data(ListBuilder<MasterServiceResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseListMasterServiceResponseBuilder() {
    ApiResponseListMasterServiceResponse._defaults(this);
  }

  ApiResponseListMasterServiceResponseBuilder get _$this {
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
  void replace(ApiResponseListMasterServiceResponse other) {
    _$v = other as _$ApiResponseListMasterServiceResponse;
  }

  @override
  void update(
      void Function(ApiResponseListMasterServiceResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListMasterServiceResponse build() => _build();

  _$ApiResponseListMasterServiceResponse _build() {
    _$ApiResponseListMasterServiceResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListMasterServiceResponse._(
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
            r'ApiResponseListMasterServiceResponse',
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
