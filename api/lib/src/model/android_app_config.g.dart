// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'android_app_config.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AndroidAppConfig extends AndroidAppConfig {
  @override
  final int minVersionCode;
  @override
  final int latestVersionCode;
  @override
  final String storeUrl;

  factory _$AndroidAppConfig(
          [void Function(AndroidAppConfigBuilder)? updates]) =>
      (AndroidAppConfigBuilder()..update(updates))._build();

  _$AndroidAppConfig._(
      {required this.minVersionCode,
      required this.latestVersionCode,
      required this.storeUrl})
      : super._();
  @override
  AndroidAppConfig rebuild(void Function(AndroidAppConfigBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AndroidAppConfigBuilder toBuilder() =>
      AndroidAppConfigBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AndroidAppConfig &&
        minVersionCode == other.minVersionCode &&
        latestVersionCode == other.latestVersionCode &&
        storeUrl == other.storeUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, minVersionCode.hashCode);
    _$hash = $jc(_$hash, latestVersionCode.hashCode);
    _$hash = $jc(_$hash, storeUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AndroidAppConfig')
          ..add('minVersionCode', minVersionCode)
          ..add('latestVersionCode', latestVersionCode)
          ..add('storeUrl', storeUrl))
        .toString();
  }
}

class AndroidAppConfigBuilder
    implements Builder<AndroidAppConfig, AndroidAppConfigBuilder> {
  _$AndroidAppConfig? _$v;

  int? _minVersionCode;
  int? get minVersionCode => _$this._minVersionCode;
  set minVersionCode(int? minVersionCode) =>
      _$this._minVersionCode = minVersionCode;

  int? _latestVersionCode;
  int? get latestVersionCode => _$this._latestVersionCode;
  set latestVersionCode(int? latestVersionCode) =>
      _$this._latestVersionCode = latestVersionCode;

  String? _storeUrl;
  String? get storeUrl => _$this._storeUrl;
  set storeUrl(String? storeUrl) => _$this._storeUrl = storeUrl;

  AndroidAppConfigBuilder() {
    AndroidAppConfig._defaults(this);
  }

  AndroidAppConfigBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _minVersionCode = $v.minVersionCode;
      _latestVersionCode = $v.latestVersionCode;
      _storeUrl = $v.storeUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AndroidAppConfig other) {
    _$v = other as _$AndroidAppConfig;
  }

  @override
  void update(void Function(AndroidAppConfigBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AndroidAppConfig build() => _build();

  _$AndroidAppConfig _build() {
    final _$result = _$v ??
        _$AndroidAppConfig._(
          minVersionCode: BuiltValueNullFieldError.checkNotNull(
              minVersionCode, r'AndroidAppConfig', 'minVersionCode'),
          latestVersionCode: BuiltValueNullFieldError.checkNotNull(
              latestVersionCode, r'AndroidAppConfig', 'latestVersionCode'),
          storeUrl: BuiltValueNullFieldError.checkNotNull(
              storeUrl, r'AndroidAppConfig', 'storeUrl'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
