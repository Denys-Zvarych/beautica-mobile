// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_pending_invite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListPendingInviteResponse
    extends ApiResponseListPendingInviteResponse {
  @override
  final bool? success;
  @override
  final BuiltList<PendingInviteResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListPendingInviteResponse(
          [void Function(ApiResponseListPendingInviteResponseBuilder)?
              updates]) =>
      (ApiResponseListPendingInviteResponseBuilder()..update(updates))._build();

  _$ApiResponseListPendingInviteResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListPendingInviteResponse rebuild(
          void Function(ApiResponseListPendingInviteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListPendingInviteResponseBuilder toBuilder() =>
      ApiResponseListPendingInviteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListPendingInviteResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListPendingInviteResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListPendingInviteResponseBuilder
    implements
        Builder<ApiResponseListPendingInviteResponse,
            ApiResponseListPendingInviteResponseBuilder> {
  _$ApiResponseListPendingInviteResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<PendingInviteResponse>? _data;
  ListBuilder<PendingInviteResponse> get data =>
      _$this._data ??= ListBuilder<PendingInviteResponse>();
  set data(ListBuilder<PendingInviteResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListPendingInviteResponseBuilder() {
    ApiResponseListPendingInviteResponse._defaults(this);
  }

  ApiResponseListPendingInviteResponseBuilder get _$this {
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
  void replace(ApiResponseListPendingInviteResponse other) {
    _$v = other as _$ApiResponseListPendingInviteResponse;
  }

  @override
  void update(
      void Function(ApiResponseListPendingInviteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListPendingInviteResponse build() => _build();

  _$ApiResponseListPendingInviteResponse _build() {
    _$ApiResponseListPendingInviteResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListPendingInviteResponse._(
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
            r'ApiResponseListPendingInviteResponse',
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
