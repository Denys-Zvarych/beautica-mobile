// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_effective_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListEffectiveDayResponse
    extends ApiResponseListEffectiveDayResponse {
  @override
  final bool? success;
  @override
  final BuiltList<EffectiveDayResponse>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListEffectiveDayResponse(
          [void Function(ApiResponseListEffectiveDayResponseBuilder)?
              updates]) =>
      (ApiResponseListEffectiveDayResponseBuilder()..update(updates))._build();

  _$ApiResponseListEffectiveDayResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListEffectiveDayResponse rebuild(
          void Function(ApiResponseListEffectiveDayResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListEffectiveDayResponseBuilder toBuilder() =>
      ApiResponseListEffectiveDayResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListEffectiveDayResponse &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListEffectiveDayResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListEffectiveDayResponseBuilder
    implements
        Builder<ApiResponseListEffectiveDayResponse,
            ApiResponseListEffectiveDayResponseBuilder> {
  _$ApiResponseListEffectiveDayResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<EffectiveDayResponse>? _data;
  ListBuilder<EffectiveDayResponse> get data =>
      _$this._data ??= ListBuilder<EffectiveDayResponse>();
  set data(ListBuilder<EffectiveDayResponse>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListEffectiveDayResponseBuilder() {
    ApiResponseListEffectiveDayResponse._defaults(this);
  }

  ApiResponseListEffectiveDayResponseBuilder get _$this {
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
  void replace(ApiResponseListEffectiveDayResponse other) {
    _$v = other as _$ApiResponseListEffectiveDayResponse;
  }

  @override
  void update(
      void Function(ApiResponseListEffectiveDayResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListEffectiveDayResponse build() => _build();

  _$ApiResponseListEffectiveDayResponse _build() {
    _$ApiResponseListEffectiveDayResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListEffectiveDayResponse._(
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
        throw BuiltValueNestedFieldError(r'ApiResponseListEffectiveDayResponse',
            _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
