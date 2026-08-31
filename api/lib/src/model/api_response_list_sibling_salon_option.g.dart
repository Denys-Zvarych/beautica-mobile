// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_list_sibling_salon_option.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponseListSiblingSalonOption
    extends ApiResponseListSiblingSalonOption {
  @override
  final bool? success;
  @override
  final BuiltList<SiblingSalonOption>? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponseListSiblingSalonOption(
          [void Function(ApiResponseListSiblingSalonOptionBuilder)? updates]) =>
      (ApiResponseListSiblingSalonOptionBuilder()..update(updates))._build();

  _$ApiResponseListSiblingSalonOption._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponseListSiblingSalonOption rebuild(
          void Function(ApiResponseListSiblingSalonOptionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponseListSiblingSalonOptionBuilder toBuilder() =>
      ApiResponseListSiblingSalonOptionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponseListSiblingSalonOption &&
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
    return (newBuiltValueToStringHelper(r'ApiResponseListSiblingSalonOption')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponseListSiblingSalonOptionBuilder
    implements
        Builder<ApiResponseListSiblingSalonOption,
            ApiResponseListSiblingSalonOptionBuilder> {
  _$ApiResponseListSiblingSalonOption? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  ListBuilder<SiblingSalonOption>? _data;
  ListBuilder<SiblingSalonOption> get data =>
      _$this._data ??= ListBuilder<SiblingSalonOption>();
  set data(ListBuilder<SiblingSalonOption>? data) => _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponseListSiblingSalonOptionBuilder() {
    ApiResponseListSiblingSalonOption._defaults(this);
  }

  ApiResponseListSiblingSalonOptionBuilder get _$this {
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
  void replace(ApiResponseListSiblingSalonOption other) {
    _$v = other as _$ApiResponseListSiblingSalonOption;
  }

  @override
  void update(
      void Function(ApiResponseListSiblingSalonOptionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponseListSiblingSalonOption build() => _build();

  _$ApiResponseListSiblingSalonOption _build() {
    _$ApiResponseListSiblingSalonOption _$result;
    try {
      _$result = _$v ??
          _$ApiResponseListSiblingSalonOption._(
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
            r'ApiResponseListSiblingSalonOption', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
