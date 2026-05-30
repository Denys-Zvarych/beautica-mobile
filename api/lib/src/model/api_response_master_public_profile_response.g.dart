// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_master_public_profile_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseMasterPublicProfileResponse
    extends ApiResponseMasterPublicProfileResponse {
  @override
  final bool? success;
  @override
  final MasterPublicProfileResponse? data;
  @override
  final String? message;

  factory _$ApiResponseMasterPublicProfileResponse(
          [void Function(ApiResponseMasterPublicProfileResponseBuilder)?
              updates]) =>
      (ApiResponseMasterPublicProfileResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseMasterPublicProfileResponse._(
      {this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseMasterPublicProfileResponse rebuild(
          void Function(ApiResponseMasterPublicProfileResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseMasterPublicProfileResponseBuilder toBuilder() =>
      ApiResponseMasterPublicProfileResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseMasterPublicProfileResponse &&
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
            r'ApiResponseMasterPublicProfileResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseMasterPublicProfileResponseBuilder
    implements
        Builder<ApiResponseMasterPublicProfileResponse,
            ApiResponseMasterPublicProfileResponseBuilder> {
  _$ApiResponseMasterPublicProfileResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  MasterPublicProfileResponseBuilder? _data;
  MasterPublicProfileResponseBuilder get data =>
      _$this._data ??= MasterPublicProfileResponseBuilder();
  set data(MasterPublicProfileResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseMasterPublicProfileResponseBuilder() {
    ApiResponseMasterPublicProfileResponse._defaults(this);
  }

  ApiResponseMasterPublicProfileResponseBuilder get _$this {
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
  void replace(ApiResponseMasterPublicProfileResponse other) {
    _$v = other as _$ApiResponseMasterPublicProfileResponse;
  }

  @override
  void update(
      void Function(ApiResponseMasterPublicProfileResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseMasterPublicProfileResponse build() => _build();

  _$ApiResponseMasterPublicProfileResponse _build() {
    _$ApiResponseMasterPublicProfileResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseMasterPublicProfileResponse._(
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
            r'ApiResponseMasterPublicProfileResponse',
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
