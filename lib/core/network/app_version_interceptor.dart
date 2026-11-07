// Phase 438 D6 — `X-App-Version: <version>+<buildNumber>` on every request.
//
// The backend (phase 437, `RequestIdFilter`) validates the value, puts it in
// the MDC and tags Sentry events with `app.version`, so a server error can be
// tied to the exact build that sent it. The backend NEVER rejects a request
// over this header, and neither does this interceptor: if the platform read
// fails, the request simply goes out without it.
//
// The value is read ONCE (memoised future) from [PackageInfo]; later requests
// reuse it. Order: right after `RequestIdInterceptor` in the `dioProvider`
// chain. NOT on `refreshDioProvider`, which stays interceptor-free by design.

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_version/app_version_info.dart';

/// Header the backend reads (`RequestIdFilter`, phase 437).
const String kAppVersionHeader = 'X-App-Version';

final class AppVersionInterceptor extends Interceptor {
  AppVersionInterceptor(this._loadPackageInfo);

  final Future<PackageInfo> Function() _loadPackageInfo;

  Future<String?>? _pending;
  bool _resolved = false;
  String? _value;

  Future<String?> _headerValue() => _pending ??= _resolve();

  Future<String?> _resolve() async {
    String? value;
    try {
      value = appVersionHeaderValue(await _loadPackageInfo());
    } on Object {
      // Informational header only — never fail or delay a request over it.
      value = null;
    }
    _value = value;
    _resolved = true;
    return value;
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Synchronous after the first resolution: only the first request(s) of
    // the process wait for the one platform read.
    final String? value = _resolved ? _value : await _headerValue();
    if (value != null) options.headers[kAppVersionHeader] = value;
    handler.next(options);
  }
}
