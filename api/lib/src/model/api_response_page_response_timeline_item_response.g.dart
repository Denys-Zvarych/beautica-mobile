// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_response_page_response_timeline_item_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiResponsePageResponseTimelineItemResponse
    extends ApiResponsePageResponseTimelineItemResponse {
  @override
  final bool? success;
  @override
  final PageResponseTimelineItemResponse? data;
  @override
  final String? message;
  @override
  final BuiltMap<String, String>? errors;

  factory _$ApiResponsePageResponseTimelineItemResponse(
          [void Function(ApiResponsePageResponseTimelineItemResponseBuilder)?
              updates]) =>
      (ApiResponsePageResponseTimelineItemResponseBuilder()..update(updates))
          ._build();

  _$ApiResponsePageResponseTimelineItemResponse._(
      {this.success, this.data, this.message, this.errors})
      : super._();
  @override
  ApiResponsePageResponseTimelineItemResponse rebuild(
          void Function(ApiResponsePageResponseTimelineItemResponseBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiResponsePageResponseTimelineItemResponseBuilder toBuilder() =>
      ApiResponsePageResponseTimelineItemResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiResponsePageResponseTimelineItemResponse &&
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
            r'ApiResponsePageResponseTimelineItemResponse')
          ..add('success', success)
          ..add('data', data)
          ..add('message', message)
          ..add('errors', errors))
        .toString();
  }
}

class ApiResponsePageResponseTimelineItemResponseBuilder
    implements
        Builder<ApiResponsePageResponseTimelineItemResponse,
            ApiResponsePageResponseTimelineItemResponseBuilder> {
  _$ApiResponsePageResponseTimelineItemResponse? _$v;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  PageResponseTimelineItemResponseBuilder? _data;
  PageResponseTimelineItemResponseBuilder get data =>
      _$this._data ??= PageResponseTimelineItemResponseBuilder();
  set data(PageResponseTimelineItemResponseBuilder? data) =>
      _$this._data = data;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, String>? _errors;
  MapBuilder<String, String> get errors =>
      _$this._errors ??= MapBuilder<String, String>();
  set errors(MapBuilder<String, String>? errors) => _$this._errors = errors;

  ApiResponsePageResponseTimelineItemResponseBuilder() {
    ApiResponsePageResponseTimelineItemResponse._defaults(this);
  }

  ApiResponsePageResponseTimelineItemResponseBuilder get _$this {
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
  void replace(ApiResponsePageResponseTimelineItemResponse other) {
    _$v = other as _$ApiResponsePageResponseTimelineItemResponse;
  }

  @override
  void update(
      void Function(ApiResponsePageResponseTimelineItemResponseBuilder)?
          updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiResponsePageResponseTimelineItemResponse build() => _build();

  _$ApiResponsePageResponseTimelineItemResponse _build() {
    _$ApiResponsePageResponseTimelineItemResponse _$result;
    try {
      _$result = _$v ??
          _$ApiResponsePageResponseTimelineItemResponse._(
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
            r'ApiResponsePageResponseTimelineItemResponse',
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
