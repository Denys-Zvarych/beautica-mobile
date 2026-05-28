// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_invite_preview_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseInvitePreviewResponse
    extends ApiResponseInvitePreviewResponse {
  @override
  final bool? success;
  @override
  final InvitePreviewResponse? data;
  @override
  final String? message;

  factory _$ApiResponseInvitePreviewResponse(
          [void Function(ApiResponseInvitePreviewResponseBuilder)? updates]) =>
      (ApiResponseInvitePreviewResponseBuilder()..update(updates))._build();

  _$ApiResponseInvitePreviewResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseInvitePreviewResponse rebuild(
          void Function(ApiResponseInvitePreviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseInvitePreviewResponseBuilder toBuilder() =>
      ApiResponseInvitePreviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseInvitePreviewResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseInvitePreviewResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseInvitePreviewResponseBuilder
    implements
        Builder<ApiResponseInvitePreviewResponse,
            ApiResponseInvitePreviewResponseBuilder> {
  _$ApiResponseInvitePreviewResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  InvitePreviewResponseBuilder? _data;
  InvitePreviewResponseBuilder get data =>
      _$this._data ??= InvitePreviewResponseBuilder();
  set data(InvitePreviewResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseInvitePreviewResponseBuilder() {
    ApiResponseInvitePreviewResponse._defaults(this);
  }

  ApiResponseInvitePreviewResponseBuilder get _$this {
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
  void replace(ApiResponseInvitePreviewResponse other) {
    _$v = other as _$ApiResponseInvitePreviewResponse;
  }

  @override
  void update(void Function(ApiResponseInvitePreviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseInvitePreviewResponse build() => _build();

  _$ApiResponseInvitePreviewResponse _build() {
    _$ApiResponseInvitePreviewResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseInvitePreviewResponse._(
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
            r'ApiResponseInvitePreviewResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
