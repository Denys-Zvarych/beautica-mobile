// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_salon_invite_history_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseSalonInviteHistoryResponse
    extends ApiResponseSalonInviteHistoryResponse {
  @override
  final bool? success;
  @override
  final SalonInviteHistoryResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseSalonInviteHistoryResponse(
          [void Function(ApiResponseSalonInviteHistoryResponseBuilder)?
              updates]) =>
      (ApiResponseSalonInviteHistoryResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseSalonInviteHistoryResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseSalonInviteHistoryResponse rebuild(
          void Function(ApiResponseSalonInviteHistoryResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseSalonInviteHistoryResponseBuilder toBuilder() =>
      ApiResponseSalonInviteHistoryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseSalonInviteHistoryResponse &&
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
            r'ApiResponseSalonInviteHistoryResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseSalonInviteHistoryResponseBuilder
    implements
        Builder<ApiResponseSalonInviteHistoryResponse,
            ApiResponseSalonInviteHistoryResponseBuilder> {
  _$ApiResponseSalonInviteHistoryResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  SalonInviteHistoryResponseBuilder? _data;
  SalonInviteHistoryResponseBuilder get data =>
      _$this._data ??= SalonInviteHistoryResponseBuilder();
  set data(SalonInviteHistoryResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseSalonInviteHistoryResponseBuilder() {
    ApiResponseSalonInviteHistoryResponse._defaults(this);
  }

  ApiResponseSalonInviteHistoryResponseBuilder get _$this {
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
  void replace(ApiResponseSalonInviteHistoryResponse other) {
    _$v = other as _$ApiResponseSalonInviteHistoryResponse;
  }

  @override
  void update(
      void Function(ApiResponseSalonInviteHistoryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseSalonInviteHistoryResponse build() => _build();

  _$ApiResponseSalonInviteHistoryResponse _build() {
    _$ApiResponseSalonInviteHistoryResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseSalonInviteHistoryResponse._(
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
            r'ApiResponseSalonInviteHistoryResponse',
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
