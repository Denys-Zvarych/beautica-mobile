// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_salon_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListSalonResponse extends ApiResponseListSalonResponse {
  @override
  final bool? success;
  @override
  final BuiltList<SalonResponse>? data;
  @override
  final String? message;

  factory _$ApiResponseListSalonResponse(
          [void Function(ApiResponseListSalonResponseBuilder)? updates]) =>
      (ApiResponseListSalonResponseBuilder()..update(updates))._build();

  _$ApiResponseListSalonResponse._({this.success, this.data, this.message})
      : super._();
  @override
  ApiResponseListSalonResponse rebuild(
          void Function(ApiResponseListSalonResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListSalonResponseBuilder toBuilder() =>
      ApiResponseListSalonResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListSalonResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListSalonResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message))
        .toString();
  }
}

class ApiResponseListSalonResponseBuilder
    implements
        Builder<ApiResponseListSalonResponse,
            ApiResponseListSalonResponseBuilder> {
  _$ApiResponseListSalonResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<SalonResponse>? _data;
  ListBuilder<SalonResponse> get data =>
      _$this._data ??= ListBuilder<SalonResponse>();
  set data(ListBuilder<SalonResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  ApiResponseListSalonResponseBuilder() {
    ApiResponseListSalonResponse._defaults(this);
  }

  ApiResponseListSalonResponseBuilder get _$this {
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
  void replace(ApiResponseListSalonResponse other) {
    _$v = other as _$ApiResponseListSalonResponse;
  }

  @override
  void update(void Function(ApiResponseListSalonResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListSalonResponse build() => _build();

  _$ApiResponseListSalonResponse _build() {
    _$ApiResponseListSalonResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListSalonResponse._(
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
            r'ApiResponseListSalonResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
