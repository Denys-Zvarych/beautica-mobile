// M515 (AUTH-D14 / AUTH-54) — attaches a Firebase App Check token to the
// SMS-sending requests listed in `app_check_paths.dart`, and to nothing else.
//
// The token comes from [AppCheckTokenSource] (production:
// `FirebaseAppCheck.instance.getLimitedUseToken()` — a fresh single-use token
// per request, AUTH-D27 d; the backend refuses a replayed `jti`).
// When Firebase is not initialised (push-less build without
// `google-services.json`) or the SDK throws, the request goes out WITHOUT the
// header and the backend decides: the local backend runs App Check OFF, so
// local flows keep working; staging / prod in ENFORCE answer 403
// APP_CHECK_FAILED, which `ErrorMapperInterceptor` maps to
// `PhoneIdentityFailure` — a 403 never enters the 401-only refresh / logout
// path. The reason for a missing token is logged once per app run.

import 'dart:developer';

import 'package:dio/dio.dart';

import '../config/app_check_config.dart';
import 'app_check_paths.dart';

/// Returns an App Check token, or `null` when none is available.
typedef AppCheckTokenSource = Future<String?> Function();

final class AppCheckInterceptor extends Interceptor {
  AppCheckInterceptor(this._tokenSource);

  final AppCheckTokenSource _tokenSource;

  bool _loggedMissing = false;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!isAppCheckPath(options.path)) {
      handler.next(options);
      return;
    }
    // A retried request (e.g. after a 401 refresh) reuses its options: drop
    // the previous — already spent, limited-use — token first, so a failed
    // fetch below never resends it (AUTH-D27 d replay).
    options.headers.remove(kAppCheckHeader);
    String? token;
    String? reason;
    try {
      token = await _tokenSource();
      if (token == null || token.isEmpty) reason = 'no token';
    } on Object catch (e) {
      reason = e.runtimeType.toString();
    }
    if (token != null && token.isNotEmpty) {
      options.headers[kAppCheckHeader] = token;
    } else if (!_loggedMissing) {
      _loggedMissing = true;
      log(
        'App Check token unavailable ($reason); sending without it',
        name: 'core.appcheck',
        level: 900,
      );
    }
    handler.next(options);
  }
}
