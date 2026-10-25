// Phase 408 (R.1, D3) — build-flavor / baked-URL consistency guard.
//
// One codebase builds two installable apps (`staging`, `prod`). The flavor
// (Android `productFlavors`, surfaced to Dart as `appFlavor`) and the values
// baked from `config/env/<env>.json` (`BEAUTICA_ENV`, `BEAUTICA_BASE_URL`) can
// be passed independently on the command line, so a build can disagree with
// itself — e.g. the `prod` APK talking to staging. This guard fails such a build
// at startup, before `runApp`.
//
//  - release / profile: any mismatch THROWS ([StateError]).
//  - debug: a mismatch is LOGGED, never thrown, so `flutter run` keeps working.
//    A missing `appFlavor` (plain `flutter run`, no `--flavor`) is tolerated in
//    debug only.
//  - the `prod` flavor additionally refuses a loopback / RFC 1918 / `*staging*`
//    host in EVERY mode, debug included (it can never legitimately talk to one).
//
// The check itself ([checkEnvConsistency]) is pure — flavor, env, URL and build
// mode are parameters — so it is unit-testable; [EnvGuard.assertConsistent] wires
// the real values. URL host classification is reused from [AppConfig]; there is
// no parallel normaliser.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

import 'app_config.dart';

/// Build mode as seen by the guard (mirrors `kDebugMode` / `kProfileMode` /
/// `kReleaseMode`, injectable for tests).
enum EnvBuildMode { debug, profile, release }

/// Allow-list: the single API host each environment may talk to.
const Map<String, String> kEnvApiHosts = <String, String>{
  'staging': 'beautica-backend-staging.up.railway.app',
  'prod': 'api.beautica.app',
};

/// Outcome of [checkEnvConsistency].
@immutable
final class EnvCheckResult {
  const EnvCheckResult({required this.errors, required this.fatalInEveryMode});

  /// Human-readable violations (empty = consistent).
  final List<String> errors;

  /// True when a violation must throw even in debug (the `prod` flavor
  /// pointing at a loopback / private / staging host).
  final bool fatalInEveryMode;

  bool get ok => errors.isEmpty;
}

/// Pure consistency check — no logging, no throwing, no globals.
EnvCheckResult checkEnvConsistency({
  required String? flavor,
  required String env,
  required String baseUrl,
  required EnvBuildMode mode,
}) {
  final List<String> errors = <String>[];
  var fatal = false;
  final bool strict = mode != EnvBuildMode.debug;
  final String host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';

  // The prod flavor may never talk to a dev/staging host — in any build mode.
  if (flavor == 'prod') {
    if (AppConfig.isPrivateOrLoopbackUrl(baseUrl) ||
        host.contains('staging') ||
        host.isEmpty) {
      errors.add(
        'flavor prod refuses base URL "$baseUrl" '
        '(loopback / private / staging / empty host)',
      );
      fatal = true;
    }
  }

  if (flavor == null) {
    // Missing appFlavor: plain `flutter run` is fine in debug only.
    if (strict) {
      errors.add(
        'appFlavor is missing in a ${mode.name} build — build with --flavor',
      );
    }
    return EnvCheckResult(errors: errors, fatalInEveryMode: fatal);
  }

  final String? allowedHost = kEnvApiHosts[flavor];
  if (allowedHost == null) {
    errors.add(
      'unknown flavor "$flavor" (expected ${kEnvApiHosts.keys.join('|')})',
    );
  } else {
    if (env != flavor) {
      errors.add('BEAUTICA_ENV "$env" does not match flavor "$flavor"');
    }
    final bool hostMismatch = host != allowedHost;
    // Documented dev workflow: staging flavor, debug, local backend override.
    final bool localDev =
        flavor == 'staging' &&
        mode == EnvBuildMode.debug &&
        AppConfig.isPrivateOrLoopbackUrl(baseUrl);
    if (hostMismatch && !localDev && !(fatal && flavor == 'prod')) {
      errors.add(
        'base URL host "$host" is not the $flavor API host "$allowedHost"',
      );
    }
  }
  return EnvCheckResult(errors: errors, fatalInEveryMode: fatal);
}

abstract final class EnvGuard {
  /// Runs [checkEnvConsistency] against the real build values. Call first in
  /// `main`, before `runApp`.
  ///
  /// Throws [StateError] on a violation in release/profile, or on a
  /// prod-flavor violation in any mode; logs in debug otherwise.
  static void assertConsistent() {
    const EnvBuildMode mode = kReleaseMode
        ? EnvBuildMode.release
        : kProfileMode
        ? EnvBuildMode.profile
        : EnvBuildMode.debug;
    apply(
      checkEnvConsistency(
        flavor: appFlavor,
        env: AppConfig.env,
        baseUrl: AppConfig.baseUrl,
        mode: mode,
      ),
      mode,
    );
  }

  /// Throws or logs per [result] and [mode]. Exposed for tests.
  @visibleForTesting
  static void apply(EnvCheckResult result, EnvBuildMode mode) {
    if (result.ok) return;
    final String message = 'Environment guard: ${result.errors.join('; ')}';
    if (mode != EnvBuildMode.debug || result.fatalInEveryMode) {
      throw StateError(message);
    }
    log(message, name: 'core.config', level: 900);
  }
}
