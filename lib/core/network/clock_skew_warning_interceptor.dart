// 2026-08-02 — debug-only device/server clock-skew diagnostic.
//
// The user asked whether the app should compare the device clock to the
// backend's and correct for drift. A PRODUCTION server-time offset was
// REJECTED: the HTTP `Date` header has only 1-second granularity, there is no
// round-trip (RTT) compensation available from a plain response header, and a
// miscomputed offset would silently corrupt every timestamp the app derives
// on that device — trading a rare, visible clock-skew symptom for a rare,
// invisible data-corruption one. This is the bounded, SAFE version instead:
// a `kDebugMode`-only diagnostic log, nothing more.
//
// THIS VALUE IS NEVER TRUSTED OR APPLIED. No code path reads, stores, or
// derives a "corrected" clock from this comparison — it exists purely so a
// developer debugging a Kyiv-day-derivation report can rule out (or confirm)
// "the test device's clock is just wrong" before chasing a code bug. Compare
// against `shared/time/kyiv_day.dart`: THAT file is how the app answers "what
// day is it" correctly; this file only ever WARNS that the device's answer to
// "what time is it" might be off.

import 'dart:developer';
import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Threshold above which a device/server clock difference is logged.
const Duration kClockSkewWarnThreshold = Duration(minutes: 5);

/// Debug-only interceptor that warns when the device clock disagrees with the
/// server's `Date` response header by more than [kClockSkewWarnThreshold].
/// Diagnostics only — see the file header.
final class ClockSkewWarningInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (kDebugMode) _warnIfSkewed(response);
    handler.next(response);
  }

  void _warnIfSkewed(Response<dynamic> response) {
    final String? dateHeader = response.headers.value('date');
    if (dateHeader == null) return;
    final DateTime serverTime;
    try {
      serverTime = HttpDate.parse(dateHeader);
    } catch (_) {
      // Diagnostics only — a malformed Date header must never crash the
      // interceptor chain or block the real response from reaching the app.
      return;
    }
    // instant-ok: diagnostic-only clock-skew comparison, never trusted/applied
    final DateTime deviceTime = DateTime.now().toUtc();
    final Duration skew = deviceTime.difference(serverTime);
    if (skew.abs() > kClockSkewWarnThreshold) {
      // mobile-security (2026-08-02 audit): logs the skew MAGNITUDE only —
      // that alone carries the full diagnostic value ("is the device clock
      // off, and by how much"). The raw device/server ISO timestamps this
      // used to log are dropped: they are the only new log surface this
      // change introduces, and while not PII, there is no debugging need
      // they serve that `skew.inMinutes` (plus the sign, which already says
      // whether the DEVICE is ahead or behind) does not.
      final String direction = skew.isNegative ? 'behind' : 'ahead';
      log(
        'Device/server clock skew ${skew.inMinutes.abs()}min ($direction) — '
        'diagnostics only, never applied to any date derivation.',
        name: 'network.clockskew',
        level: 900,
      );
    }
  }
}
