// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_user_profile_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseUserProfileResponse extends ApiResponseUserProfileResponse {
  @override
  final bool? success;
  @override
  final UserProfileResponse? data;
  @override
  final String? message;

  factory _$ApiResponseUserProfileResponse(
          [void Function(ApiResponseUserProfileResponseBuilder)? updates]) =>
      (ApiResponseUserProfileResponseBuilder()..update(updates))._build();

  _$ApiResponseUserProfileResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseUserProfileResponse rebuild(
          void Function(ApiResponseUserProfileResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseUserProfileResponseBuilder toBuilder() =>
      ApiResponseUserProfileResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseUserProfileResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseUserProfileResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseUserProfileResponseBuilder
    implements
        Builder<ApiResponseUserProfileResponse,
            ApiResponseUserProfileResponseBuilder> {
  _$ApiResponseUserProfileResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  UserProfileResponseBuilder? _data;
  UserProfileResponseBuilder get data =>
      _$this._data ??= UserProfileResponseBuilder();
  set data(UserProfileResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseUserProfileResponseBuilder() {
    ApiResponseUserProfileResponse._defaults(this);
  }

  ApiResponseUserProfileResponseBuilder get _$this {
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
  void replace(ApiResponseUserProfileResponse other) {
    _$v = other as _$ApiResponseUserProfileResponse;
  }

  @override
  void update(void Function(ApiResponseUserProfileResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseUserProfileResponse build() => _build();

  _$ApiResponseUserProfileResponse _build() {
    _$ApiResponseUserProfileResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseUserProfileResponse._(
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
            r'ApiResponseUserProfileResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
