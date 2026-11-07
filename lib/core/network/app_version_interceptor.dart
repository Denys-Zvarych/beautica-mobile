// Phase 438 D6 — `X-App-Version: <version>+<buildNumber>` on every request.
//
// The backend (phase 437, `RequestIdFilter`) validates the value, puts it in
// the MDC and tags Sentry events with `app.version`, so a server error can be
// tied to the exact build that sent it. The backend NEVER rejects a request
// over this header, and neither does this interceptor.
//
// SYNCHRONOUS BY CONTRACT: [onRequest] only PEEKS at an already-resolved
// [PackageInfo] — it never awaits and never creates a timer. A request sent
// before the one platform read resolves (or after it failed) simply goes out
// without the header. Awaiting here once blocked every main-Dio request in
// widget tests that do not override the platform read (pumpAndSettle
// timeouts, pending timers in goldens). `main.dart` starts the read before
// `runApp` without awaiting it.
//
// Order: right after `RequestIdInterceptor` in the `dioProvider` chain. NOT on
// `refreshDioProvider`, which stays interceptor-free by design.

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_version/app_version_info.dart';

/// Header the backend reads (`RequestIdFilter`, phase 437).
const String kAppVersionHeader = 'X-App-Version';

final class AppVersionInterceptor extends Interceptor {
  /// [_peek] returns the resolved [PackageInfo], or `null` while it is still
  /// loading or when the platform read failed. It must not block.
  AppVersionInterceptor(this._peek);

  final PackageInfo? Function() _peek;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final PackageInfo? info = _peek();
    if (info != null) {
      options.headers[kAppVersionHeader] = appVersionHeaderValue(info);
    }
    handler.next(options);
  }
}
