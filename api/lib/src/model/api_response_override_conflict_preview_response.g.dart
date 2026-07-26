// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_override_conflict_preview_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseOverrideConflictPreviewResponse
    extends ApiResponseOverrideConflictPreviewResponse {
  @override
  final bool? success;
  @override
  final OverrideConflictPreviewResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseOverrideConflictPreviewResponse(
          [void Function(ApiResponseOverrideConflictPreviewResponseBuilder)?
              updates]) =>
      (ApiResponseOverrideConflictPreviewResponseBuilder()..update(updates))
          ._build();

  _$ApiResponseOverrideConflictPreviewResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseOverrideConflictPreviewResponse rebuild(
          void Function(ApiResponseOverrideConflictPreviewResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseOverrideConflictPreviewResponseBuilder toBuilder() =>
      ApiResponseOverrideConflictPreviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseOverrideConflictPreviewResponse &&
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
            r'ApiResponseOverrideConflictPreviewResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseOverrideConflictPreviewResponseBuilder
    implements
        Builder<ApiResponseOverrideConflictPreviewResponse,
            ApiResponseOverrideConflictPreviewResponseBuilder> {
  _$ApiResponseOverrideConflictPreviewResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  OverrideConflictPreviewResponseBuilder? _data;
  OverrideConflictPreviewResponseBuilder get data =>
      _$this._data ??= OverrideConflictPreviewResponseBuilder();
  set data(OverrideConflictPreviewResponseBuilder? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseOverrideConflictPreviewResponseBuilder() {
    ApiResponseOverrideConflictPreviewResponse._defaults(this);
  }

  ApiResponseOverrideConflictPreviewResponseBuilder get _$this {
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
  void replace(ApiResponseOverrideConflictPreviewResponse other) {
    _$v = other as _$ApiResponseOverrideConflictPreviewResponse;
  }

  @override
  void update(
      void Function(ApiResponseOverrideConflictPreviewResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseOverrideConflictPreviewResponse build() => _build();

  _$ApiResponseOverrideConflictPreviewResponse _build() {
    _$ApiResponseOverrideConflictPreviewResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponseOverrideConflictPreviewResponse._(
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
            r'ApiResponseOverrideConflictPreviewResponse',
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
