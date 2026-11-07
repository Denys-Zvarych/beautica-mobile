// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppConfigResponse extends AppConfigResponse {
  @override
  final AndroidAppConfig android;

  factory _$AppConfigResponse(
          [void Function(AppConfigResponseBuilder)? updates]) =>
      (AppConfigResponseBuilder()..update(updates))._build();

  _$AppConfigResponse._({required this.android}) : super._();
  @override
  AppConfigResponse rebuild(void Function(AppConfigResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppConfigResponseBuilder toBuilder() =>
      AppConfigResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppConfigResponse && android == other.android;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, android.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppConfigResponse')
          ..add('android', android))
        .toString();
  }
}

class AppConfigResponseBuilder
    implements Builder<AppConfigResponse, AppConfigResponseBuilder> {
  _$AppConfigResponse? _$v;

  AndroidAppConfigBuilder? _android;
  AndroidAppConfigBuilder get android =>
      _$this._android ??= AndroidAppConfigBuilder();
  set android(AndroidAppConfigBuilder? android) => _$this._android = android;

  AppConfigResponseBuilder() {
    AppConfigResponse._defaults(this);
  }

  AppConfigResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _android = $v.android.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppConfigResponse other) {
    _$v = other as _$AppConfigResponse;
  }

  @override
  void update(void Function(AppConfigResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppConfigResponse build() => _build();

  _$AppConfigResponse _build() {
    _$AppConfigResponse _$result;
    try {
      _$result = _$v ??
          _$AppConfigResponse._(
            android: android.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'android';
        android.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AppConfigResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
