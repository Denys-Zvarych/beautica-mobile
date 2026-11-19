// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_registration_ticket_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseRegistrationTicketResponse
    extends ApiResponseRegistrationTicketResponse {
  @override
  final bool? success;
  @override
  final RegistrationTicketResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;
  @override
  final String? requestId;

  factory _$ApiResponseRegistrationTicketResponse(
          [void Function(ApiResponseRegistrationTicketResponseBuilder)?
              updates]) =>
      (ApiResponseRegistrationTicketResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseRegistrationTicketResponse._(
      {this.success, this.data, this.message, this.errors, this.requestId})
      : super._();
  @override
  ApiResponseRegistrationTicketResponse rebuild(
          void Function(ApiResponseRegistrationTicketResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseRegistrationTicketResponseBuilder toBuilder() =>
      ApiResponseRegistrationTicketResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseRegistrationTicketResponse &&
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
            r'ApiResponseRegistrationTicketResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors)
          ..add('requestId', requestId))
        .toString();
  }
}

class ApiResponseRegistrationTicketResponseBuilder
    implements
        Builder<ApiResponseRegistrationTicketResponse,
            ApiResponseRegistrationTicketResponseBuilder> {
  _$ApiResponseRegistrationTicketResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  RegistrationTicketResponseBuilder? _data;
  RegistrationTicketResponseBuilder get data =>
      _$this._data ??= RegistrationTicketResponseBuilder();
  set data(RegistrationTicketResponseBuilder? data) => _$this._data = data;

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

  ApiResponseRegistrationTicketResponseBuilder() {
    ApiResponseRegistrationTicketResponse._defaults(this);
  }

  ApiResponseRegistrationTicketResponseBuilder get _$this {
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
  void replace(ApiResponseRegistrationTicketResponse other) {
    _$v = other as _$ApiResponseRegistrationTicketResponse;
  }

  @override
  void update(
      void Function(ApiResponseRegistrationTicketResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseRegistrationTicketResponse build() => _build();

  _$ApiResponseRegistrationTicketResponse _build() {
    _$ApiResponseRegistrationTicketResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseRegistrationTicketResponse._(
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
            r'ApiResponseRegistrationTicketResponse',
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
