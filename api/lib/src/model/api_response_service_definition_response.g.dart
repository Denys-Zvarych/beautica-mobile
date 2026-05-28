// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_service_definition_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseServiceDefinitionResponse
    extends ApiResponseServiceDefinitionResponse {
  @override
  final bool? success;
  @override
  final ServiceDefinitionResponse? data;
  @override
  final String? message;

  factory _$ApiResponseServiceDefinitionResponse(
          [void Function(ApiResponseServiceDefinitionResponseBuilder)?
              updates]) =>
      (ApiResponseServiceDefinitionResponseBuilder()..update(updates))._build();

  _$ApiResponseServiceDefinitionResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseServiceDefinitionResponse rebuild(
          void Function(ApiResponseServiceDefinitionResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseServiceDefinitionResponseBuilder toBuilder() =>
      ApiResponseServiceDefinitionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseServiceDefinitionResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseServiceDefinitionResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseServiceDefinitionResponseBuilder
    implements
        Builder<ApiResponseServiceDefinitionResponse,
            ApiResponseServiceDefinitionResponseBuilder> {
  _$ApiResponseServiceDefinitionResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ServiceDefinitionResponseBuilder? _data;
  ServiceDefinitionResponseBuilder get data =>
      _$this._data ??= ServiceDefinitionResponseBuilder();
  set data(ServiceDefinitionResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseServiceDefinitionResponseBuilder() {
    ApiResponseServiceDefinitionResponse._defaults(this);
  }

  ApiResponseServiceDefinitionResponseBuilder get _$this {
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
  void replace(ApiResponseServiceDefinitionResponse other) {
    _$v = other as _$ApiResponseServiceDefinitionResponse;
  }

  @override
  void update(
      void Function(ApiResponseServiceDefinitionResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseServiceDefinitionResponse build() => _build();

  _$ApiResponseServiceDefinitionResponse _build() {
    _$ApiResponseServiceDefinitionResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseServiceDefinitionResponse._(
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
            r'ApiResponseServiceDefinitionResponse',
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
