// Phase 438 — the forced-update verdict.
//
// D1 compare: the pubspec `+N` build number (Android versionCode) against the
//    backend's `android.minVersionCode`; block only when build < min. An
//    unparsable build number never blocks.
// D2 fetch: `GET /api/v1/app/config` through [appConfigApiProvider] (the main
//    pinned Dio, [kAppConfigTimeout] = 10 s timeouts). ANY failure — timeout, no network, 404 (a
//    backend without 437), 429, 5xx, malformed body — before the first
//    successful check resolves to [UpdateGateState.ok]: the gate FAILS OPEN.
//    A failure AFTER a successful check keeps that last verdict (going
//    offline must not lift a "required" gate). The verdict lives in memory
//    only, so an offline cold start can never block.
// D3 when: once at cold start (scheduled from `build`, never awaited before
//    the first frame — the state starts `ok`), then on every
//    `AppLifecycleState.resumed` whose last SUCCESSFUL check is older than
//    [kUpdateGateRecheckInterval] (or that never succeeded). Concurrent checks
//    share one request.
//    Cold-start retry: while NO check has ever succeeded, a failed check
//    schedules a retry after [kUpdateGateRetryDelays] (3 s, 10 s, 30 s — at
//    most 3 in the process). Any check that starts (resume, retry, manual)
//    cancels a pending retry, so there is never a second request; a success
//    or dispose cancels it too. Once a check succeeded there are no retries.
//    The first check runs from a microtask, not a post-frame callback: the
//    overlay first reads the gate inside the first build, so the microtask is
//    already off the frame path, and a post-frame callback registered while no
//    frame is scheduled (provider first read in the background) would never
//    fire — breaking "once per launch".
// D4 placement: read by `UpdateGateOverlay` in the `MaterialApp.router`
//    builder — no route, no router rebuild, no auth watch.

import 'dart:async';
import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../network/api_client_provider.dart';
import '../time/clock_provider.dart';
import 'app_version_info.dart';

part 'update_gate_provider.freezed.dart';
part 'update_gate_provider.g.dart';

/// Minimum age of the last successful check before a resume re-checks.
const Duration kUpdateGateRecheckInterval = Duration(hours: 1);

/// Backoff of the retries after a failed check while no check has ever
/// succeeded; its length is the retry cap.
const List<Duration> kUpdateGateRetryDelays = <Duration>[
  Duration(seconds: 3),
  Duration(seconds: 10),
  Duration(seconds: 30),
];

/// The gate verdict.
@freezed
sealed class UpdateGateState with _$UpdateGateState {
  /// The app renders normally (also every fail-open outcome).
  const factory UpdateGateState.ok() = UpdateGateOk;

  /// The installed build is below the backend minimum — only the gate shows.
  const factory UpdateGateState.required({
    required String packageName,
    required String installedVersion,
    required String storeUrl,
  }) = UpdateGateRequired;
}

/// The pure compare (D1): `true` only when [buildNumber] parses and is below
/// [minVersionCode].
bool isUpdateRequired({
  required String buildNumber,
  required int minVersionCode,
}) {
  final int? build = parseBuildNumber(buildNumber);
  return build != null && build < minVersionCode;
}

@Riverpod(keepAlive: true)
class UpdateGate extends _$UpdateGate {
  Future<void>? _inFlight;
  DateTime? _lastSuccessAt;
  Timer? _retryTimer;
  int _retriesScheduled = 0;

  @override
  UpdateGateState build() {
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: _onResume,
    );
    ref.onDispose(lifecycle.dispose);
    ref.onDispose(_cancelRetry);
    // Deferred: a provider must not mutate itself inside build(), and the
    // first frame must not wait for the network.
    Future<void>.microtask(() {
      if (ref.mounted) unawaited(check());
    });
    return const UpdateGateState.ok();
  }

  void _onResume() {
    final DateTime? last = _lastSuccessAt;
    if (last != null) {
      final Duration elapsed = ref.read(clockProvider)().difference(last);
      // A wall clock moved backwards gives a negative elapsed: treat it as
      // stale (re-check) rather than suppressing every re-check until the
      // clock catches up.
      if (!elapsed.isNegative && elapsed < kUpdateGateRecheckInterval) return;
    }
    unawaited(check());
  }

  /// Runs one check (shared by concurrent callers). Never throws.
  Future<void> check() => _inFlight ??= _check().whenComplete(() {
    _inFlight = null;
  });

  Future<void> _check() async {
    // This check supersedes a pending retry: never two requests.
    _cancelRetry();
    final UpdateGateState? next = await _evaluate();
    if (!ref.mounted) return;
    if (next != null) {
      state = next;
    } else if (_lastSuccessAt == null) {
      // No verdict has ever succeeded in this process: fail OPEN (D2), and
      // try again soon rather than waiting for a resume.
      state = const UpdateGateState.ok();
      _scheduleRetry();
    }
    // Otherwise a failed RE-check keeps the last successful verdict, so going
    // offline cannot lift a "required" gate.
  }

  void _scheduleRetry() {
    if (_retriesScheduled >= kUpdateGateRetryDelays.length) return;
    final Duration delay = kUpdateGateRetryDelays[_retriesScheduled];
    _retriesScheduled++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (ref.mounted) unawaited(check());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// The verdict, or `null` when the check failed (no usable answer).
  Future<UpdateGateState?> _evaluate() async {
    try {
      final PackageInfo info = await ref.read(appPackageInfoProvider.future);
      final Response<ApiResponseAppConfigResponse> response = await ref
          .read(appConfigApiProvider)
          .getConfig();
      final AndroidAppConfig? android = response.data?.data?.android;
      if (response.statusCode != 200 || android == null) return null;
      _lastSuccessAt = ref.read(clockProvider)();
      if (!isUpdateRequired(
        buildNumber: info.buildNumber,
        minVersionCode: android.minVersionCode,
      )) {
        return const UpdateGateState.ok();
      }
      log(
        'Update required: build ${info.buildNumber} < '
        'min ${android.minVersionCode}',
        name: 'core.update_gate',
        level: 800,
      );
      return UpdateGateState.required(
        packageName: info.packageName,
        installedVersion: info.version,
        storeUrl: android.storeUrl,
      );
    } on Object catch (error) {
      // Fail OPEN (D2). The type only — never a URL or response body.
      log(
        'Update check failed: ${error.runtimeType}',
        name: 'core.update_gate',
        level: 800,
      );
      // Types only — no URL, header, body or PII.
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'update_gate',
            level: SentryLevel.warning,
            message: 'Update check failed',
            data: <String, dynamic>{
              'error_type': error.runtimeType.toString(),
              if (error is DioException) 'dio_type': error.type.name,
            },
          ),
        ),
      );
      return null;
    }
  }
}
